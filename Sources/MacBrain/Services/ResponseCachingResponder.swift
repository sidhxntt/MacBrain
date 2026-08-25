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
        let history = conversation.suffix(8).map { "\($0.role.rawValue):\(Self.normalize($0.text))" }.joined(separator: "\n")
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
                guard Self.isCacheable(prompt) else {
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
                    if !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    private static func isCacheable(_ prompt: String) -> Bool {
        if LocalFileReadTool.isFileContentRequest(prompt) { return false }
        let normalized = prompt.lowercased()
        if !LiveMacQueryRouter().capabilities(for: prompt).isEmpty { return false }
        let volatileTerms = ["current", "now", "today", "latest", "live", "who am i", "this mac", "my mac", "system configuration"]
        return !volatileTerms.contains { normalized.contains($0) }
    }
}
