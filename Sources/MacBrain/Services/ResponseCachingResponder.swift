import CryptoKit
import Foundation

protocol SourceRevisionProviding: Sendable {
    func currentSourceRevision() async -> String
}

extension LocalSourceRepository: SourceRevisionProviding {}

protocol ResponseCaching: Sendable {
    func response(for key: ResponseCacheKey) async -> String?
    func store(_ response: String, for key: ResponseCacheKey) async
}

struct ResponseCacheKey: Sendable, Hashable {
    let value: String
    let model: String
    let sourceRevision: String

    init(prompt: String, conversation: [ChatMessage], model: String, sourceRevision: String) {
        self.model = model
        self.sourceRevision = sourceRevision
        let history = conversation.suffix(8).map { message in
            let grounding = message.groundingSourceIDs.sorted().joined(separator: ",")
            return "\(message.role.rawValue):\(Self.normalize(message.text)):grounding=\(grounding)"
        }.joined(separator: "\n")
        let material = [model, sourceRevision, history, Self.normalize(prompt)].joined(separator: "\n---\n")
        value = Self.digest(material)
    }

    private static func normalize(_ input: String) -> String {
        input
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func digest(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

actor InMemoryResponseCache: ResponseCaching {
    private var responses: [ResponseCacheKey: String] = [:]

    func response(for key: ResponseCacheKey) -> String? { responses[key] }

    func store(_ response: String, for key: ResponseCacheKey) {
        responses[key] = response
    }
}

actor LocalResponseCache: ResponseCaching {
    private let database: MacBrainDatabase

    init(database: MacBrainDatabase) {
        self.database = database
    }

    func response(for key: ResponseCacheKey) async -> String? {
        try? await database.cachedResponse(for: key.value)
    }

    func store(_ response: String, for key: ResponseCacheKey) async {
        try? await database.saveCachedResponse(
            response,
            key: key.value,
            model: key.model,
            sourceRevision: key.sourceRevision
        )
    }
}

struct ResponseCachingResponder: ChatResponder {
    let upstream: any ChatResponder
    let cache: any ResponseCaching
    let sourceRevisionProvider: any SourceRevisionProviding
    let selectedModel: @MainActor @Sendable () -> String
    let queryPlanner: LocalQueryPlanner

    init(
        upstream: any ChatResponder,
        cache: any ResponseCaching,
        sourceRevisionProvider: any SourceRevisionProviding,
        selectedModel: @escaping @MainActor @Sendable () -> String,
        queryPlanner: LocalQueryPlanner = LocalQueryPlanner()
    ) {
        self.upstream = upstream
        self.cache = cache
        self.sourceRevisionProvider = sourceRevisionProvider
        self.selectedModel = selectedModel
        self.queryPlanner = queryPlanner
    }

    func respond(to prompt: String) async throws -> String {
        var response = ""
        for try await token in stream(to: prompt) { response.append(token) }
        return response
    }

    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        stream(to: prompt, conversation: [])
    }

    func stream(to prompt: String, conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                if let privacyResponse = PrivacyPromptPolicy.response(for: prompt) {
                    continuation.yield(privacyResponse)
                    continuation.finish()
                    return
                }

                let plan = queryPlanner.plan(
                    prompt: prompt,
                    records: [],
                    conversation: conversation
                )
                guard Self.isCacheable(plan, prompt: prompt) else {
                    await Self.forward(upstream.stream(to: prompt, conversation: conversation), to: continuation)
                    return
                }

                let model = await selectedModel()
                let revision = await sourceRevisionProvider.currentSourceRevision()
                let key = ResponseCacheKey(
                    prompt: prompt,
                    conversation: conversation,
                    model: model,
                    sourceRevision: revision
                )

                if let cached = await cache.response(for: key) {
                    continuation.yield(cached)
                    continuation.finish()
                    return
                }

                var response = ""
                do {
                    for try await token in upstream.stream(to: prompt, conversation: conversation) {
                        try Task.checkCancellation()
                        response.append(token)
                        continuation.yield(token)
                    }
                    if Self.isReusable(response) {
                        await cache.store(response, for: key)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: OllamaClientError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func forward(
        _ stream: AsyncThrowingStream<String, Error>,
        to continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            for try await token in stream {
                try Task.checkCancellation()
                continuation.yield(token)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: OllamaClientError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private static func isCacheable(_ plan: LocalQueryPlan, prompt: String) -> Bool {
        if LocalFileReadTool.isFileContentRequest(prompt) { return false }
        switch plan {
        case .system, .restricted, .connectorCapability, .connector:
            return false
        case .evidenceSearch, .casual:
            return true
        }
    }

    private static func isReusable(_ response: String) -> Bool {
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let transientMarkers = [
            "i couldn't complete that local response",
            "i couldn't find matching material",
            "i found relevant local material, but i couldn't verify",
            "didn't respond in time",
            "check ollama in settings"
        ]
        return !transientMarkers.contains { normalized.contains($0) }
    }
}
