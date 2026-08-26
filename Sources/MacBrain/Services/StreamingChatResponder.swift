import Foundation
import OSLog

struct StreamingChatResponder: ChatResponder {
    private static let logger = Logger(subsystem: "com.macbrain.app", category: "chat-routing")

    let provider: any InferenceProvider
    let repository: LocalSourceRepository
    let selectedModel: @MainActor @Sendable () -> String
    let selectedEmbeddingModel: @MainActor @Sendable () -> String
    let fallback: any ChatResponder
    let systemProfileProvider: any SystemProfileProviding
    let liveContextProvider: any LiveMacContextProviding
    let minimumLiveResponseDelay: Duration
    let providerStatusTimeout: Duration
    let retrievalTimeout: Duration

    init(
        provider: any InferenceProvider,
        repository: LocalSourceRepository,
        selectedModel: @escaping @MainActor @Sendable () -> String,
        selectedEmbeddingModel: @escaping @MainActor @Sendable () -> String = { "nomic-embed-text" },
        fallback: any ChatResponder,
        systemProfileProvider: any SystemProfileProviding = LocalSystemProfileProvider(),
        liveContextProvider: any LiveMacContextProviding = LocalLiveMacContextProvider(),
        minimumLiveResponseDelay: Duration = .zero,
        providerStatusTimeout: Duration = .seconds(8),
        retrievalTimeout: Duration = .seconds(3)
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
        self.retrievalTimeout = retrievalTimeout
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
                let requestStartedAt = ContinuousClock.now
                let route = ChatQueryIntentRouter().route(prompt: prompt, conversation: conversation)
                Self.logger.info(
                    "intent=\(route.intent.rawValue, privacy: .public) reason=\(route.reason, privacy: .public)"
                )

                if route.intent == .restricted,
                   let privacyResponse = PrivacyPromptPolicy.response(for: prompt) {
                    continuation.yield(privacyResponse)
                    continuation.finish()
                    Self.logTerminal("restricted", startedAt: requestStartedAt)
                    return
                }

                let systemProfile = systemProfileProvider.currentProfile()
                if route.intent == .liveMac {
                    let liveRouter = LiveMacQueryRouter()
                    let capabilities = liveRouter.capabilities(for: prompt)
                    let response: String
                    if capabilities.isEmpty {
                        response = systemProfile.markdownSummary
                    } else {
                        let snapshot = await liveContextProvider.snapshot(for: capabilities)
                        response = liveRouter.response(to: prompt, snapshot: snapshot, profile: systemProfile)
                            ?? systemProfile.markdownSummary
                    }
                    await Self.waitForLiveResponseMinimum(
                        from: requestStartedAt,
                        minimumDelay: minimumLiveResponseDelay
                    )
                    guard !Task.isCancelled else { return }
                    continuation.yield(response)
                    continuation.finish()
                    Self.logTerminal("live-ready", startedAt: requestStartedAt)
                    return
                }

                if route.intent == .explicitLocal,
                   let response = await LocalFileReadTool(repository: repository).response(for: prompt) {
                    continuation.yield(response)
                    continuation.finish()
                    Self.logTerminal("file-ready", startedAt: requestStartedAt)
                    return
                }

                let selectedModel = await selectedModel()
                let providerStatus = await Self.status(
                    of: provider,
                    timeout: providerStatusTimeout
                )
                guard case let .ready(models) = providerStatus, models.contains(where: { $0.name == selectedModel }) else {
                    continuation.yield(Self.providerUnavailableMessage)
                    continuation.finish()
                    Self.logTerminal("provider-unavailable", startedAt: requestStartedAt)
                    return
                }

                var retrieval = EvidenceSearchResult.empty
                var usesGroundedHistory = false
                switch route.intent {
                case .explicitLocal:
                    if route.reason == "follow-up to grounded answer" {
                        retrieval = Self.inheritedEvidence(from: conversation)
                        usesGroundedHistory = !retrieval.evidence.isEmpty
                    }
                    if retrieval.evidence.isEmpty {
                        retrieval = await Self.retrieveEvidence(
                            prompt,
                            repository: repository,
                            provider: provider,
                            embeddingModel: await selectedEmbeddingModel(),
                            timeout: retrievalTimeout
                        )
                    }
                    guard !retrieval.evidence.isEmpty else {
                        continuation.yield("I couldn't find matching material in your connected local sources.")
                        continuation.finish()
                        Self.logTerminal("local-no-evidence", startedAt: requestStartedAt)
                        return
                    }
                case .implicitLocal:
                    let lexical = await Self.retrieveLexicalEvidence(
                        prompt,
                        repository: repository,
                        timeout: retrievalTimeout
                    )
                    let acceptance = EvidenceAcceptancePolicy().evaluate(
                        prompt: prompt,
                        intent: route.intent,
                        lexical: lexical
                    )
                    Self.logger.info(
                        "lexical_count=\(lexical.evidence.count) accepted=\(acceptance.accepted) reason=\(acceptance.reason, privacy: .public)"
                    )
                    if acceptance.accepted {
                        retrieval = await Self.retrieveEvidence(
                            prompt,
                            repository: repository,
                            provider: provider,
                            embeddingModel: await selectedEmbeddingModel(),
                            timeout: retrievalTimeout
                        )
                        if retrieval.evidence.isEmpty { retrieval = lexical }
                        usesGroundedHistory = true
                    }
                case .casual, .general, .liveMac, .restricted:
                    break
                }

                let messages = Self.messages(
                    prompt: prompt,
                    conversation: conversation,
                    retrieval: retrieval,
                    systemProfile: systemProfile,
                    allowGroundedHistory: usesGroundedHistory || !retrieval.evidence.isEmpty
                )
                await forward(
                    provider.streamChat(model: selectedModel, messages: messages),
                    to: continuation,
                    evidence: retrieval.evidence,
                    startedAt: requestStartedAt
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func forward(
        _ stream: AsyncThrowingStream<String, Error>,
        to continuation: AsyncThrowingStream<String, Error>.Continuation,
        evidence: [RetrievalEvidence] = [],
        startedAt: ContinuousClock.Instant
    ) async {
        do {
            var answer = ""
            for try await token in stream {
                try Task.checkCancellation()
                answer.append(token)
                if evidence.isEmpty { continuation.yield(token) }
            }
            if !evidence.isEmpty {
                if CitationValidator.hasValidCitation(in: answer, evidence: evidence) {
                    continuation.yield(answer)
                    let sources = CitationValidator.renderedSources(for: answer, evidence: evidence)
                    if !sources.isEmpty { continuation.yield("\n\n" + sources) }
                } else {
                    continuation.yield(Self.directEvidenceFallback(evidence))
                }
            }
            continuation.finish()
            Self.logTerminal("ready", startedAt: startedAt)
        } catch is CancellationError {
            continuation.finish(throwing: OllamaClientError.cancelled)
            Self.logTerminal("cancelled", startedAt: startedAt)
        } catch {
            continuation.finish(throwing: error)
            Self.logTerminal("failed", startedAt: startedAt)
        }
    }

    private static func directEvidenceFallback(_ evidence: [RetrievalEvidence]) -> String {
        let boundedEvidence = Array(evidence.prefix(3))
        let excerpts = boundedEvidence.map { evidence in
            "- [\(evidence.citationID)] \(evidence.sourceTitle): \(cleanedExcerpt(evidence.excerpt))"
        }.joined(separator: "\n\n")
        let sources = CitationValidator.renderedSources(for: boundedEvidence)
        return "I found relevant local material, but I couldn't verify a grounded answer from the local model.\n\n\(excerpts)\n\n\(sources)"
    }

    private static func cleanedExcerpt(_ excerpt: String) -> String {
        let withoutMarkup = excerpt
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"file://\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[[A-Za-z]\d+\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "```", with: " ")
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(withoutMarkup.prefix(300))
    }

    private static func messages(
        prompt: String,
        conversation: [ChatMessage],
        retrieval: EvidenceSearchResult,
        systemProfile: SystemProfile,
        allowGroundedHistory: Bool
    ) -> [InferenceChatMessage] {
        let context = retrieval.evidence.map { evidence in
            let excerpt = evidence.excerpt.replacingOccurrences(of: "\n", with: " ")
            return "[\(evidence.citationID)] \(evidence.sourceTitle) | \(evidence.sourceType) | \(evidence.sourcePath)\n\(excerpt)"
        }.joined(separator: "\n\n")
        let instruction = context.isEmpty
            ? "You are MacBrain, a fast, capable assistant running entirely on this Mac. Answer ordinary questions directly using your general knowledge. Use concise Markdown: match answer length to the question, prefer short paragraphs or 3–6 bullets, and never repeat the local profile, local evidence, or this instruction unless asked. When a question asks about the user or this Mac, use the local Mac context below. Do not invent facts about selected local sources when none are available."
            : "You are MacBrain, a fast, capable assistant running entirely on this Mac. Use only the selected local evidence for factual claims about the user's sources. Cite every such claim with its exact citation ID (for example, [S1]); never invent an ID. If the evidence is incomplete or conflicts, say so explicitly instead of presenting a claim as fact. Use concise Markdown and do not repeat the evidence.\n\nSelected local evidence:\n\(context)\n\nRetrieval confidence: \(retrieval.isLowConfidence ? "low — clearly state uncertainty" : "sufficient")"
        let eligibleHistory = allowGroundedHistory
            ? conversation
            : conversation.filter { $0.groundingSourceIDs.isEmpty }
        let history = PromptBudgetPolicy().boundedHistory(eligibleHistory).map { message in
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
        let startedAt = ContinuousClock.now
        let race = ProviderStatusTimeoutRace()
        let work = Task {
            await race.resolve(await provider.status())
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                work.cancel()
                logger.notice("stage=provider-status outcome=timeout")
                await race.resolve(.unavailable("MacBrain could not confirm the local model in time."))
            } catch {
                return
            }
        }
        let result = await race.wait()
        watchdog.cancel()
        let outcome: String
        switch result {
        case .ready: outcome = "ready"
        case .checking: outcome = "checking"
        case .runtimeMissing: outcome = "runtime-missing"
        case .unavailable: outcome = "unavailable"
        }
        logger.info(
            "stage=provider-status outcome=\(outcome, privacy: .public) duration=\(String(describing: startedAt.duration(to: .now)), privacy: .public)"
        )
        return result
    }

    /// Search is optional context for an ordinary chat request. A database write
    /// (for example, a Photo sync) must never hold the user-facing response
    /// hostage; continue without retrieved evidence when that budget expires.
    private static func retrieveEvidence(
        _ prompt: String,
        repository: LocalSourceRepository,
        provider: any InferenceProvider,
        embeddingModel: String,
        timeout: Duration
    ) async -> EvidenceSearchResult {
        let startedAt = ContinuousClock.now
        let race = EvidenceTimeoutRace()
        let work = Task {
            await race.resolve(
                await repository.searchEvidence(prompt, using: provider, embeddingModel: embeddingModel)
            )
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                work.cancel()
                logger.notice("stage=hybrid-retrieval outcome=timeout")
                await race.resolve(.empty)
            } catch {
                return
            }
        }
        let result = await race.wait()
        watchdog.cancel()
        logger.info(
            "stage=hybrid-retrieval evidence_count=\(result.evidence.count, privacy: .public) duration=\(String(describing: startedAt.duration(to: .now)), privacy: .public)"
        )
        return result
    }

    private static func retrieveLexicalEvidence(
        _ prompt: String,
        repository: LocalSourceRepository,
        timeout: Duration
    ) async -> EvidenceSearchResult {
        let startedAt = ContinuousClock.now
        let race = EvidenceTimeoutRace()
        let work = Task {
            await race.resolve(await repository.searchLexicalEvidence(prompt))
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                work.cancel()
                logger.notice("stage=lexical-retrieval outcome=timeout")
                await race.resolve(.empty)
            } catch {
                return
            }
        }
        let result = await race.wait()
        watchdog.cancel()
        logger.info(
            "stage=lexical-retrieval evidence_count=\(result.evidence.count, privacy: .public) duration=\(String(describing: startedAt.duration(to: .now)), privacy: .public)"
        )
        return result
    }

    private static func inheritedEvidence(from conversation: [ChatMessage]) -> EvidenceSearchResult {
        guard let message = conversation.last(where: {
            $0.role == .assistant && !$0.groundingSourceIDs.isEmpty
        }) else { return .empty }

        let allowedIDs = Set(message.groundingSourceIDs)
        let cards = ChatCitationCard.parse(from: message.text).filter {
            allowedIDs.contains($0.citationID)
        }
        guard !cards.isEmpty else { return .empty }
        let answer = message.text.components(separatedBy: "### Sources").first ?? message.text
        let excerpt = String(answer.prefix(1_200)).trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence = cards.enumerated().map { index, card in
            RetrievalEvidence(
                citationID: card.citationID,
                chunkID: UUID(),
                sourceTitle: card.title,
                sourceType: "conversation",
                sourcePath: card.url.path,
                sourceDate: message.createdAt,
                excerpt: excerpt,
                startOffset: 0,
                endOffset: excerpt.utf16.count,
                pageNumber: nil,
                score: 1 / Double(index + 1)
            )
        }
        return EvidenceSearchResult(evidence: evidence, isLowConfidence: false)
    }

    private static func logTerminal(_ category: String, startedAt: ContinuousClock.Instant) {
        let elapsed = String(describing: startedAt.duration(to: .now))
        logger.info("terminal=\(category, privacy: .public) duration=\(elapsed, privacy: .public)")
    }

    private static let providerUnavailableMessage =
        "I couldn't complete that local response because Ollama or the selected model is unavailable. Check Ollama in Settings, then try again."
}

enum PrivacyPromptPolicy {
    static func response(for prompt: String) -> String? {
        let normalized = prompt.lowercased()

        if containsAny(normalized, ["password", "token", "secret", "private key"])
            && containsAny(normalized, ["every", "all", "list", "find"])
        {
            return "I can’t bulk-extract passwords, tokens, secrets, or private keys. Ask about a specific non-sensitive item instead."
        }

        if normalized.contains("did not authorize") || normalized.contains("didn't authorize") || normalized.contains("unconnected source") {
            return "I can only use sources you explicitly connected and authorized."
        }

        if normalized.contains("everything about everyone") {
            return "Please narrow this to a specific connected source, person, or question."
        }

        return nil
    }

    private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}

private actor EvidenceTimeoutRace {
    private var result: EvidenceSearchResult?
    private var continuation: CheckedContinuation<EvidenceSearchResult, Never>?

    func wait() async -> EvidenceSearchResult {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            if let result {
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func resolve(_ result: EvidenceSearchResult) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor ProviderStatusTimeoutRace {
    private var result: InferenceProviderStatus?
    private var continuation: CheckedContinuation<InferenceProviderStatus, Never>?

    func wait() async -> InferenceProviderStatus {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            if let result {
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func resolve(_ result: InferenceProviderStatus) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}
