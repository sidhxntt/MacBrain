import Foundation
import XCTest
@testable import MacBrain

final class StreamingChatResponderTests: XCTestCase {
    func testReadyProviderStreamsLocalTokens() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: StreamingProvider(statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]), tokens: ["Local", " answer"]),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let tokens = try await collect(responder.stream(to: "What changed?"))

        XCTAssertEqual(tokens, ["Local", " answer"])
    }

    func testUnavailableProviderFallsBackToLocalEvidenceResponder() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: StreamingProvider(statusValue: .runtimeMissing, tokens: []),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let tokens = try await collect(responder.stream(to: "What changed?"))

        XCTAssertEqual(tokens, ["Fallback local answer"])
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var tokens: [String] = []
        for try await token in stream { tokens.append(token) }
        return tokens
    }

    private func temporaryRepositoryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sources.json")
    }
}

private struct StreamingProvider: InferenceProvider {
    let statusValue: InferenceProviderStatus
    let tokens: [String]

    func status() async -> InferenceProviderStatus { statusValue }
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }
}

private struct FallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Fallback local answer" }
}
