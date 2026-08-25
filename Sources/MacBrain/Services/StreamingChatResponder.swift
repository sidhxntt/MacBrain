import Foundation

struct StreamingChatResponder: ChatResponder {
    let provider: any InferenceProvider
    let repository: LocalSourceRepository
    let selectedModel: @MainActor @Sendable () -> String
    let fallback: any ChatResponder

    init(
        provider: any InferenceProvider,
        repository: LocalSourceRepository,
        selectedModel: @escaping @MainActor @Sendable () -> String,
        fallback: any ChatResponder
    ) {
        self.provider = provider
        self.repository = repository
        self.selectedModel = selectedModel
        self.fallback = fallback
    }

    func respond(to prompt: String) async throws -> String {
        var response = ""
        for try await token in stream(to: prompt) { response.append(token) }
        return response
    }

    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let selectedModel = await selectedModel()
                let providerStatus = await provider.status()
                guard case let .ready(models) = providerStatus, models.contains(where: { $0.name == selectedModel }) else {
                    await forward(fallback.stream(to: prompt), to: continuation)
                    return
                }

                let evidence = await repository.search(prompt)
                let messages = Self.messages(prompt: prompt, evidence: evidence)
                await forward(provider.streamChat(model: selectedModel, messages: messages), to: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func forward(
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

    private static func messages(prompt: String, evidence: [ConnectorDocument]) -> [InferenceChatMessage] {
        let context = evidence.prefix(4).map { document in
            let excerpt = document.text.replacingOccurrences(of: "\n", with: " ")
            return "[\(document.sourceLabel): \(document.title)] \(String(excerpt.prefix(1_500)))"
        }.joined(separator: "\n\n")
        let instruction = context.isEmpty
            ? "You are MacBrain, a local assistant. Be clear about uncertainty when no local evidence is available."
            : "You are MacBrain, a local assistant. Answer only from this local evidence. Cite source titles in plain language and state uncertainty when evidence is incomplete.\n\n\(context)"
        return [.system(instruction), .user(prompt)]
    }
}
