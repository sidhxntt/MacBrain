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

    func testLocalOllamaCanAnswerFromInjectedMacContext() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_LIVE_OLLAMA"] == "1",
            "Set MACBRAIN_LIVE_OLLAMA=1 to exercise the local Ollama service."
        )

        let profile = SystemProfile(
            userDisplayName: "Alex",
            computerName: "Alex’s MacBook Pro",
            hardwareModel: "Mac16,7",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.0 (Build 25A123)",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN",
            timeZoneIdentifier: "Asia/Kolkata"
        )
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: OllamaProvider(client: OllamaClient(retryLimit: 0)),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: LocalMockChatResponder(),
            systemProfileProvider: LiveTestSystemProfileProvider(profile: profile)
        )

        var response = ""
        for try await token in responder.stream(to: "Reply with only this Mac’s processor name.") {
            response += token
        }

        XCTAssertTrue(response.localizedCaseInsensitiveContains("M5 Pro"))
    }

    private func temporaryRepositoryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sources.json")
    }
}

private struct LiveTestSystemProfileProvider: SystemProfileProviding {
    let profile: SystemProfile

    func currentProfile() -> SystemProfile { profile }
}
