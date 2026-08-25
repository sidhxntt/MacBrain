import Foundation

struct StreamingChatResponder: ChatResponder {
    let provider: any InferenceProvider
    let repository: LocalSourceRepository
    let selectedModel: @MainActor @Sendable () -> String
    let selectedEmbeddingModel: @MainActor @Sendable () -> String
    let fallback: any ChatResponder
    let systemProfileProvider: any SystemProfileProviding
    let liveContextProvider: any LiveMacContextProviding
    let minimumLiveResponseDelay: Duration
    let providerStatusTimeout: Duration

    init(
        provider: any InferenceProvider,
        repository: LocalSourceRepository,
        selectedModel: @escaping @MainActor @Sendable () -> String,
        selectedEmbeddingModel: @escaping @MainActor @Sendable () -> String = { "nomic-embed-text" },
        fallback: any ChatResponder,
        systemProfileProvider: any SystemProfileProviding = LocalSystemProfileProvider(),
        liveContextProvider: any LiveMacContextProviding = LocalLiveMacContextProvider(),
        minimumLiveResponseDelay: Duration = .seconds(5),
        providerStatusTimeout: Duration = .seconds(8)
    ) {
        self.provider = provider
        self.repository = repository
        self.selectedModel = selectedModel
        self.selectedEmbeddingModel = selectedEmbeddingModel
        self.fallback = fallback
        self.systemProfileProvider = systemProfileProvider
        self.liveContextProvider = liveContextProvider
        self.minimumLiveResponseDelay = minimumLiveResponseDelay
        self.providerStatusTimeout = providerStatusTimeout
    }

    func respond(to prompt: String) async throws -> String {
        var response = ""
        for try await token in stream(to: prompt) { response.append(token) }
        return response
    }

    func stream(to prompt: String) -> AsyncThrowingStream<String, Error> {
        stream(to: prompt, conversation: [])
    }

    func stream(to prompt: String, conversation: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let responseStartedAt = ContinuousClock.now
                let systemProfile = systemProfileProvider.currentProfile()
                let liveQueryRouter = LiveMacQueryRouter()
                let liveCapabilities = liveQueryRouter.capabilities(for: prompt)
                if !liveCapabilities.isEmpty {
                    let snapshot = await liveContextProvider.snapshot(for: liveCapabilities)
                    if let response = liveQueryRouter.response(to: prompt, snapshot: snapshot, profile: systemProfile) {
                        await Self.waitForLiveResponseMinimum(
                            from: responseStartedAt,
                            minimumDelay: minimumLiveResponseDelay
                        )
                        guard !Task.isCancelled else { return }
                        continuation.yield(response)
                        continuation.finish()
                        return
                    }
                }

                if prompt.isLiveMemoryQuestion, let response = systemProfile.liveMemoryResponse {
                    await Self.waitForLiveResponseMinimum(
                        from: responseStartedAt,
                        minimumDelay: minimumLiveResponseDelay
                    )
                    guard !Task.isCancelled else { return }
                    continuation.yield(response)
                    continuation.finish()
                    return
                }

                if prompt.isSystemProfileQuestion {
                    await Self.waitForLiveResponseMinimum(
                        from: responseStartedAt,
                        minimumDelay: minimumLiveResponseDelay
                    )
                    guard !Task.isCancelled else { return }
                    continuation.yield(systemProfile.markdownSummary)
                    continuation.finish()
                    return
                }

                if let response = await LocalFileReadTool(repository: repository).response(for: prompt) {
                    continuation.yield(response)
                    continuation.finish()
                    return
                }

                let selectedModel = await selectedModel()
                let selectedEmbeddingModel = await selectedEmbeddingModel()
                let providerStatus = await Self.status(
                    of: provider,
                    timeout: providerStatusTimeout
                )
                guard case let .ready(models) = providerStatus, models.contains(where: { $0.name == selectedModel }) else {
                    await forward(fallback.stream(to: prompt), to: continuation)
                    return
                }

                let retrieval = prompt.isMacStatusQuestion
                    ? EvidenceSearchResult.empty
                    : await repository.searchEvidence(prompt, using: provider, embeddingModel: selectedEmbeddingModel)
                let messages = Self.messages(
                    prompt: prompt,
                    conversation: conversation,
                    retrieval: retrieval,
                    systemProfile: systemProfile
                )
                await forward(
                    provider.streamChat(model: selectedModel, messages: messages),
                    to: continuation,
                    evidence: retrieval.evidence
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func forward(
        _ stream: AsyncThrowingStream<String, Error>,
        to continuation: AsyncThrowingStream<String, Error>.Continuation,
        evidence: [RetrievalEvidence] = []
    ) async {
        do {
            var answer = ""
            for try await token in stream {
                try Task.checkCancellation()
                answer.append(token)
                continuation.yield(token)
            }
            let citations = CitationValidator.renderedSources(for: answer, evidence: evidence)
            if !citations.isEmpty { continuation.yield(citations) }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: OllamaClientError.cancelled)
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private static func messages(
        prompt: String,
        conversation: [ChatMessage],
        retrieval: EvidenceSearchResult,
        systemProfile: SystemProfile
    ) -> [InferenceChatMessage] {
        let context = retrieval.evidence.map { evidence in
            let excerpt = evidence.excerpt.replacingOccurrences(of: "\n", with: " ")
            return "[\(evidence.citationID)] \(evidence.sourceTitle) | \(evidence.sourceType) | \(evidence.sourcePath)\n\(excerpt)"
        }.joined(separator: "\n\n")
        let instruction = context.isEmpty
            ? "You are MacBrain, a fast, capable assistant running entirely on this Mac. Answer ordinary questions directly using your general knowledge. Use concise Markdown: match answer length to the question, prefer short paragraphs or 3–6 bullets, and never repeat the local profile, local evidence, or this instruction unless asked. When a question asks about the user or this Mac, use the local Mac context below. Do not invent facts about selected local sources when none are available."
            : "You are MacBrain, a fast, capable assistant running entirely on this Mac. Use only the selected local evidence for factual claims about the user's sources. Cite every such claim with its exact citation ID (for example, [S1]); never invent an ID. If the evidence is incomplete or conflicts, say so explicitly instead of presenting a claim as fact. Use concise Markdown and do not repeat the evidence.\n\nSelected local evidence:\n\(context)\n\nRetrieval confidence: \(retrieval.isLowConfidence ? "low — clearly state uncertainty" : "sufficient")"
        let history = conversation.suffix(8).map { message in
            InferenceChatMessage(
                role: message.role == .user ? .user : .assistant,
                content: message.text
            )
        }
        return [.system("\(instruction)\n\n\(systemProfile.promptContext)")] + history + [.user(prompt)]
    }

    private static func waitForLiveResponseMinimum(from startedAt: ContinuousClock.Instant, minimumDelay: Duration) async {
        let elapsed = startedAt.duration(to: .now)
        guard elapsed < minimumDelay else { return }
        try? await Task.sleep(for: minimumDelay - elapsed)
    }

    private static func status(
        of provider: any InferenceProvider,
        timeout: Duration
    ) async -> InferenceProviderStatus {
        await withTaskGroup(of: InferenceProviderStatus.self, returning: InferenceProviderStatus.self) { group in
            group.addTask {
                await provider.status()
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .unavailable("MacBrain could not confirm the local model in time.")
                } catch {
                    return .checking
                }
            }

            let result = await group.next() ?? .unavailable("MacBrain could not confirm the local model.")
            group.cancelAll()
            return result
        }
    }
}

private extension String {
    var isSystemProfileQuestion: Bool {
        let normalized = lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "who am i"
            || normalized == "who am i?"
            || normalized.contains("who am i on this mac")
            || normalized == "tell me who i am"
            || normalized == "tell me who i am?"
    }

    var isLiveMemoryQuestion: Bool {
        let normalized = lowercased()
        return normalized.contains("ram")
            || normalized.contains("memory usage")
            || normalized.contains("memory used")
            || normalized.contains("memory free")
            || normalized.contains("free memory")
            || normalized.contains("free ram")
            || normalized.contains("used ram")
            || normalized.contains("swap")
    }

    var isMacStatusQuestion: Bool {
        let normalized = lowercased()
        return !LiveMacQueryRouter().capabilities(for: self).isEmpty
            || isLiveMemoryQuestion
            || normalized.contains("my mac")
            || normalized.contains("this mac")
            || normalized.contains("my computer")
            || normalized.contains("computer configuration")
            || normalized.contains("machine configuration")
            || normalized.contains("hardware configuration")
            || normalized.contains("macbook")
            || normalized.contains("system configuration")
            || normalized.contains("system specs")
            || normalized.contains("processor")
            || normalized.contains("cpu")
            || normalized.contains("storage")
            || normalized.contains("disk space")
            || normalized.contains("battery")
    }
}
