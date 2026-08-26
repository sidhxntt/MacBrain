import Foundation
import XCTest
@testable import MacBrain

final class LexicalFirstRetrievalTests: XCTestCase {
    func testNaturalPromptWithoutLocalPrefixUsesStrongLexicalEvidence() async throws {
        let repository = try await verifiedRepository(
            title: "ORBIT-731 launch handoff",
            text: "ORBIT-731 owner: Nila Quill",
            path: "/tmp/orbit-731.md"
        )
        let provider = LexicalFirstProvider(
            answer: "Nila Quill owns ORBIT-731. [S1]",
            embeddingBehavior: .immediate
        )
        let responder = makeResponder(repository: repository, provider: provider)

        let response = try await collect(responder.stream(to: "Who owns ORBIT-731?")).joined()

        XCTAssertTrue(response.contains("Nila Quill owns ORBIT-731. [S1]"))
        XCTAssertTrue(response.contains("### Sources"))
        XCTAssertTrue(provider.capturedMessages.contains { $0.content.contains("ORBIT-731 owner: Nila Quill") })
    }

    func testSemanticTimeoutPreservesAlreadyAcceptedLexicalEvidence() async throws {
        let repository = try await verifiedRepository(
            title: "ORBIT-731 launch handoff",
            text: "ORBIT-731 owner: Nila Quill",
            path: "/tmp/orbit-731.md"
        )
        let provider = LexicalFirstProvider(
            answer: "Nila Quill owns ORBIT-731. [S1]",
            embeddingBehavior: .nonCooperative
        )
        let responder = makeResponder(
            repository: repository,
            provider: provider,
            retrievalTimeout: .milliseconds(20)
        )
        let startedAt = ContinuousClock.now

        let response = try await collect(responder.stream(to: "Who owns ORBIT-731?")).joined()

        XCTAssertTrue(response.contains("Nila Quill owns ORBIT-731. [S1]"))
        XCTAssertTrue(response.contains("### Sources"))
        XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(250))
    }

    func testPublicKnowledgePromptWithOnlyGenericOverlapRemainsGeneral() async throws {
        let repository = try await verifiedRepository(
            title: "Kubernetes handbook",
            text: "Kubernetes is a container orchestrator. PRIVATE-LOCAL-MARKER",
            path: "/tmp/kubernetes.md"
        )
        let provider = LexicalFirstProvider(
            answer: "Kubernetes orchestrates containerized workloads.",
            embeddingBehavior: .immediate
        )
        let responder = makeResponder(repository: repository, provider: provider)

        let response = try await collect(responder.stream(to: "What is Kubernetes?")).joined()

        XCTAssertEqual(response, "Kubernetes orchestrates containerized workloads.")
        XCTAssertFalse(response.contains("PRIVATE-LOCAL-MARKER"))
        XCTAssertFalse(response.contains("### Sources"))
        XCTAssertEqual(provider.embeddingCallCount, 0)
    }

    func testUnavailableModelStillReturnsAcceptedLexicalEvidence() async throws {
        let repository = try await verifiedRepository(
            title: "ORBIT-731 launch handoff",
            text: "ORBIT-731 owner: Nila Quill",
            path: "/tmp/orbit-731.md"
        )
        let provider = LexicalFirstProvider(
            answer: "This must not be generated.",
            embeddingBehavior: .immediate,
            statusValue: .runtimeMissing
        )
        let responder = makeResponder(repository: repository, provider: provider)

        let response = try await collect(responder.stream(to: "Who owns ORBIT-731?")).joined()

        XCTAssertTrue(response.contains("ORBIT-731 owner: Nila Quill"))
        XCTAssertTrue(response.contains("### Sources"))
        XCTAssertFalse(response.contains("Ollama or the selected model is unavailable"))
        XCTAssertEqual(provider.embeddingCallCount, 0)
        XCTAssertTrue(provider.capturedMessages.isEmpty)
    }

    private func makeResponder(
        repository: LocalSourceRepository,
        provider: LexicalFirstProvider,
        retrievalTimeout: Duration = .seconds(1)
    ) -> StreamingChatResponder {
        StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: LexicalFirstFallbackResponder(),
            retrievalTimeout: retrievalTimeout
        )
    }

    private func verifiedRepository(
        title: String,
        text: String,
        path: String
    ) async throws -> LocalSourceRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-lexical-first-" + UUID().uuidString,
            isDirectory: true
        )
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
        try await repository.bootstrap()
        let record = ConnectorRecord(
            kind: .folder,
            displayName: "Verified folder",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        _ = try await repository.commitSourceGeneration(
            record: record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: path,
                    title: title,
                    text: text,
                    sourceLabel: "Verified folder",
                    modifiedAt: .now,
                    metadata: ["path": path]
                )
            ]
        )
        return repository
    }

    private func collect(
        _ stream: AsyncThrowingStream<String, Error>
    ) async throws -> [String] {
        var output: [String] = []
        for try await token in stream { output.append(token) }
        return output
    }
}

private final class LexicalFirstProvider: InferenceProvider, @unchecked Sendable {
    enum EmbeddingBehavior {
        case immediate
        case nonCooperative
    }

    private let lock = NSLock()
    private let answer: String
    private let embeddingBehavior: EmbeddingBehavior
    private let statusValue: InferenceProviderStatus
    private var embeddingCalls = 0
    private var messages: [InferenceChatMessage] = []

    init(
        answer: String,
        embeddingBehavior: EmbeddingBehavior,
        statusValue: InferenceProviderStatus = .ready(models: [
            .init(
                name: "qwen3:8b",
                size: nil,
                parameterSize: "8B",
                quantization: "Q4_K_M"
            )
        ])
    ) {
        self.answer = answer
        self.embeddingBehavior = embeddingBehavior
        self.statusValue = statusValue
    }

    var embeddingCallCount: Int {
        lock.withLock { embeddingCalls }
    }

    var capturedMessages: [InferenceChatMessage] {
        lock.withLock { messages }
    }

    func status() async -> InferenceProviderStatus {
        statusValue
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        lock.withLock { embeddingCalls += 1 }
        switch embeddingBehavior {
        case .immediate:
            return input.map { _ in .init(values: [1, 0]) }
        case .nonCooperative:
            return await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    continuation.resume(returning: input.map { _ in .init(values: [1, 0]) })
                }
            }
        }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        lock.withLock { self.messages = messages }
        return AsyncThrowingStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }
}

private struct LexicalFirstFallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Fallback" }
}
