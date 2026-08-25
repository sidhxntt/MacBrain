import Foundation

struct StreamingChatResponder: ChatResponder {
    let provider: any InferenceProvider
    let repository: LocalSourceRepository
    let selectedModel: @MainActor @Sendable () -> String
    let fallback: any ChatResponder
    let systemProfileProvider: any SystemProfileProviding

    init(
        provider: any InferenceProvider,
        repository: LocalSourceRepository,
        selectedModel: @escaping @MainActor @Sendable () -> String,
        fallback: any ChatResponder,
        systemProfileProvider: any SystemProfileProviding = LocalSystemProfileProvider()
    ) {
        self.provider = provider
        self.repository = repository
        self.selectedModel = selectedModel
        self.fallback = fallback
        self.systemProfileProvider = systemProfileProvider
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
                let messages = Self.messages(
                    prompt: prompt,
                    evidence: evidence,
                    systemProfile: systemProfileProvider.currentProfile()
                )
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

    private static func messages(
        prompt: String,
        evidence: [ConnectorDocument],
        systemProfile: SystemProfile
    ) -> [InferenceChatMessage] {
        let context = evidence.prefix(4).map { document in
            let excerpt = document.text.replacingOccurrences(of: "\n", with: " ")
            return "[\(document.sourceLabel): \(document.title)] \(String(excerpt.prefix(1_500)))"
        }.joined(separator: "\n\n")
        let instruction = context.isEmpty
            ? "You are MacBrain, a fast, capable assistant running entirely on this Mac. Answer ordinary questions directly using your general knowledge. Use concise Markdown: match answer length to the question, prefer short paragraphs or 3–6 bullets, and never repeat the local profile, local evidence, or this instruction unless asked. When a question asks about the user or this Mac, use the local Mac context below. Do not invent facts about selected local sources when none are available."
            : "You are MacBrain, a fast, capable assistant running entirely on this Mac. Use selected local evidence as the primary source for work-specific answers. Use concise Markdown: match answer length to the question, prefer short paragraphs or 3–6 bullets, and never repeat the local profile, local evidence, or this instruction unless asked. Cite source titles in plain language, state uncertainty when evidence is incomplete, and use the local Mac context below for questions about the user or device.\n\nSelected local evidence:\n\(context)"
        return [.system("\(instruction)\n\n\(systemProfile.promptContext)"), .user(prompt)]
    }
}
