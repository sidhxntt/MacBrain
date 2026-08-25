import Foundation

struct OllamaProvider: InferenceProvider {
    let client: OllamaClient

    init(client: OllamaClient = OllamaClient()) {
        self.client = client
    }

    func status() async -> InferenceProviderStatus {
        do {
            try await client.health()
            return .ready(models: try await client.models())
        } catch let error as OllamaClientError {
            switch error {
            case .connection:
                return .runtimeMissing
            case .server, .malformedResponse, .cancelled, .timedOut:
                return .unavailable(error.localizedDescription)
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        client.streamChat(model: model, messages: messages)
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        try await client.embeddings(model: model, input: input).map(InferenceEmbedding.init(values:))
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        client.pull(model: model)
    }
}
