import Foundation
import XCTest
@testable import MacBrain

@MainActor
final class InferenceStoreTests: XCTestCase {
    func testRefreshShowsRuntimeMissingState() async {
        let store = InferenceStore(provider: TestInferenceProvider(statusValue: .runtimeMissing), preferences: transientPreferences())

        await store.refresh()

        XCTAssertEqual(store.status, .runtimeMissing)
        XCTAssertTrue(store.availableModels.isEmpty)
    }

    func testRefreshMarksRequiredModelsReadyWhenInstalled() async {
        let models = [
            InferenceModel(name: "qwen3:8b", size: 5_000_000_000, parameterSize: "8B", quantization: "Q4_K_M"),
            InferenceModel(name: "nomic-embed-text", size: 274_000_000, parameterSize: nil, quantization: nil)
        ]
        let store = InferenceStore(provider: TestInferenceProvider(statusValue: .ready(models: models)), preferences: transientPreferences())

        await store.refresh()

        XCTAssertTrue(store.isReadyForLocalChat)
        XCTAssertEqual(store.selectedChatModel, "qwen3:8b")
        XCTAssertEqual(store.selectedEmbeddingModel, "nomic-embed-text")
    }

    func testDownloadUpdatesProgressAndRefreshesInstalledModels() async {
        let provider = TestInferenceProvider(
            statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]),
            pullEvents: [
                .init(status: "pulling manifest", completed: nil, total: nil),
                .init(status: "verifying", completed: 10, total: 10)
            ]
        )
        let store = InferenceStore(provider: provider, preferences: transientPreferences())

        await store.download(model: "qwen3:8b")

        XCTAssertNil(store.download)
        XCTAssertEqual(store.availableModels.map(\.name), ["qwen3:8b"])
    }

    private func transientPreferences() -> UserDefaults {
        let suite = "InferenceStoreTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        preferences.removePersistentDomain(forName: suite)
        return preferences
    }
}

private struct TestInferenceProvider: InferenceProvider {
    let statusValue: InferenceProviderStatus
    let pullEvents: [OllamaPullProgress]

    init(
        statusValue: InferenceProviderStatus,
        pullEvents: [OllamaPullProgress] = []
    ) {
        self.statusValue = statusValue
        self.pullEvents = pullEvents
    }

    func status() async -> InferenceProviderStatus {
        return statusValue
    }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { continuation in
            for event in pullEvents { continuation.yield(event) }
            continuation.finish()
        }
    }
}
