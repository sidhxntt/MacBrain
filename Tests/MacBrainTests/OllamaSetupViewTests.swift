import SwiftUI
import XCTest
@testable import MacBrain

@MainActor
final class OllamaSetupViewTests: XCTestCase {
    func testSetupViewCanBeConstructedForMissingRuntime() {
        let store = InferenceStore(provider: SetupViewProvider(), preferences: .standard)

        let view = OllamaSetupView(store: store)

        XCTAssertNotNil(view)
    }
}

private struct SetupViewProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus { .runtimeMissing }
    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }
}
