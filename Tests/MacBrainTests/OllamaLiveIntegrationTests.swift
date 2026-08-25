import Foundation
import XCTest
@testable import MacBrain

final class OllamaLiveIntegrationTests: XCTestCase {
    func testLocalOllamaServesConfiguredModelsEmbeddingAndVisibleChatTokens() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_LIVE_OLLAMA"] == "1",
            "Set MACBRAIN_LIVE_OLLAMA=1 to exercise the local Ollama service."
        )

        let client = OllamaClient(retryLimit: 0)
        try await client.health()

        let models = try await client.models().map(\.name)
        XCTAssertTrue(models.contains("qwen3:8b"))
        XCTAssertTrue(models.contains("nomic-embed-text"))

        let vectors = try await client.embeddings(model: "nomic-embed-text", input: ["MacBrain integration test"])
        XCTAssertEqual(vectors.count, 1)
        XCTAssertEqual(vectors[0].count, 768)

        var response = ""
        for try await token in client.streamChat(
            model: "qwen3:8b",
            messages: [.user("Reply with exactly: MacBrain ready")]
        ) {
            response += token
        }

        XCTAssertFalse(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
