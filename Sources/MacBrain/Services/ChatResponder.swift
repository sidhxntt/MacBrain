protocol ChatResponder: Sendable {
    func respond(to prompt: String) async throws -> String
    func stream(to prompt: String) -> AsyncThrowingStream<String, Error>
    func stream(to prompt: String, conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}

extension ChatResponder {
    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await respond(to: prompt))
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

    func stream(to prompt: String, conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        stream(to: prompt)
    }
}
