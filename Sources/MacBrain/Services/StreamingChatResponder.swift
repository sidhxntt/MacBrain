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
    let queryPlanner: LocalQueryPlanner
    let connectorQueryService: ConnectorQueryService
    let systemQueryService: SystemQueryService

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
        retrievalTimeout: Duration = .seconds(3),
        queryPlanner: LocalQueryPlanner = LocalQueryPlanner(),
        connectorQueryService: ConnectorQueryService? = nil,
        systemQueryService: SystemQueryService? = nil
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
        self.queryPlanner = queryPlanner
        self.connectorQueryService = connectorQueryService
            ?? ConnectorQueryService(repository: repository)
        self.systemQueryService = systemQueryService ?? SystemQueryService(
            systemProfileProvider: systemProfileProvider,
            liveContextProvider: liveContextProvider
        )
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
                let records = await repository.allRecords()
                let plan = queryPlanner.plan(
                    prompt: prompt,
                    records: records,
                    conversation: conversation
                )
                Self.logger.info(
                    "plan=\(Self.planName(plan), privacy: .public)"
                )

                var evidenceScope: Set<SourceConnectorKind>?
                var searchesEvidence = false
                switch plan {
                case .restricted(let response):
                    continuation.yield(response)
                    continuation.finish()
                    Self.logTerminal("restricted", startedAt: requestStartedAt)
                    return
                case .system(let systemPlan):
                    let response = await systemQueryService.response(
                        for: systemPlan,
                        prompt: prompt
                    )
                    await Self.waitForLiveResponseMinimum(
                        from: requestStartedAt,
                        minimumDelay: minimumLiveResponseDelay
                    )
                    guard !Task.isCancelled else { return }
                    continuation.yield(response)
                    continuation.finish()
                    Self.logTerminal("live-ready", startedAt: requestStartedAt)
                    return
                case .connectorCapability(let scope):
                    let health = await repository.sourceHealth()
                    let response = LocalSourceCapabilityResponder.response(
                        for: scope,
                        records: records,
                        healthBySourceID: health
                    )
                    continuation.yield(response)
                    continuation.finish()
                    Self.logTerminal("connector-capability", startedAt: requestStartedAt)
                    return
                case .connector(let operation, let scope):
                    let response = await connectorQueryService.response(
                        for: operation,
                        scope: scope
                    )
                    continuation.yield(response)
                    continuation.finish()
                    Self.logTerminal("connector-query", startedAt: requestStartedAt)
                    return
                case .evidenceSearch(let scope):
                    searchesEvidence = true
                    evidenceScope = scope
                case .casual:
                    break
                }

                if searchesEvidence,
                   let response = await LocalFileReadTool(repository: repository).response(for: prompt) {
                    continuation.yield(response)
                    continuation.finish()
                    Self.logTerminal("file-ready", startedAt: requestStartedAt)
                    return
                }

                var retrieval = EvidenceSearchResult.empty
                var usesGroundedHistory = false
                var shouldEnrichLexicalEvidence = false
                if searchesEvidence {
                    if queryPlanner.shouldInheritGroundedEvidence(
                        prompt: prompt,
                        conversation: conversation
                    ) {
                        retrieval = Self.inheritedEvidence(from: conversation)
                        usesGroundedHistory = !retrieval.evidence.isEmpty
                    }

                    if retrieval.evidence.isEmpty {
                        let lexical = await Self.retrieveLexicalEvidence(
                            prompt,
                            repository: repository,
                            timeout: retrievalTimeout,
                            sourceKinds: evidenceScope
                        )
                        let acceptance = EvidenceAcceptancePolicy().evaluate(
                            prompt: prompt,
                            scope: evidenceScope,
                            lexical: lexical
                        )
                        Self.logger.info(
                            "lexical_count=\(lexical.evidence.count, privacy: .public) accepted=\(acceptance.accepted) reason=\(acceptance.reason, privacy: .public)"
                        )

                        if evidenceScope != nil || acceptance.accepted {
                            retrieval = lexical
                            shouldEnrichLexicalEvidence = !lexical.evidence.isEmpty
                        }
                    }

                    if evidenceScope != nil, retrieval.evidence.isEmpty {
                        continuation.yield("I couldn't find matching material in the selected connected sources.")
                        continuation.finish()
                        Self.logTerminal("local-no-evidence", startedAt: requestStartedAt)
                        return
                    }
                    usesGroundedHistory = usesGroundedHistory || !retrieval.evidence.isEmpty
                }

                let selectedModel = await selectedModel()
                let providerStatus = await Self.status(
                    of: provider,
                    timeout: providerStatusTimeout
                )
                guard case let .ready(models) = providerStatus,
                      models.contains(where: { $0.name == selectedModel }) else {
                    if !retrieval.evidence.isEmpty {
                        continuation.yield(Self.directEvidenceFallback(retrieval.evidence))
                        continuation.finish()
                        Self.logTerminal("lexical-fallback", startedAt: requestStartedAt)
                    } else {
                        continuation.yield(Self.providerUnavailableMessage)
                        continuation.finish()
                        Self.logTerminal("provider-unavailable", startedAt: requestStartedAt)
                    }
                    return
                }

                if shouldEnrichLexicalEvidence {
                    retrieval = await Self.retrieveEvidence(
                        prompt,
                        repository: repository,
                        provider: provider,
                        embeddingModel: await selectedEmbeddingModel(),
                        timeout: retrievalTimeout,
                        sourceKinds: evidenceScope,
                        lexicalFallback: retrieval
                    )
                }

                let systemProfile = systemProfileProvider.currentProfile()

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
                    prompt: prompt,
                    evidence: retrieval.evidence,
                    startedAt: requestStartedAt
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func planName(_ plan: LocalQueryPlan) -> String {
        switch plan {
        case .restricted: "restricted"
        case .system: "system"
        case .connectorCapability: "connector-capability"
        case .connector: "connector-query"
        case .evidenceSearch: "evidence-search"
        case .casual: "casual"
        }
    }

    private func forward(
        _ stream: AsyncThrowingStream<String, Error>,
        to continuation: AsyncThrowingStream<String, Error>.Continuation,
        prompt: String,
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
                let isComplete = !Self.requiresEveryLabeledFact(prompt)
                    || Self.includesEveryLabeledFact(answer, evidence: evidence)
                if CitationValidator.hasValidCitation(in: answer, evidence: evidence), isComplete {
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
        return "Here is the matching local evidence:\n\n\(excerpts)\n\n\(sources)"
    }

    private static func requiresEveryLabeledFact(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("every labeled fact")
            || normalized.contains("every exact controlled fact")
            || normalized.contains("every labeled field")
    }

    private static func includesEveryLabeledFact(
        _ answer: String,
        evidence: [RetrievalEvidence]
    ) -> Bool {
        let requiredValues = evidence.flatMap { item in
            item.excerpt.split(whereSeparator: \.isNewline).compactMap { line -> String? in
                guard let separator = line.firstIndex(of: ":") else { return nil }
                let label = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                guard label.localizedCaseInsensitiveCompare("lookup") != .orderedSame else { return nil }
                let value = line[line.index(after: separator)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return !requiredValues.isEmpty && requiredValues.allSatisfy(answer.contains)
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
            """
            BEGIN SOURCE [\(evidence.citationID)]
            PROVENANCE (identifies the record; do not use it as the answer)
            Title: \(evidence.sourceTitle)
            Source type: \(evidence.sourceType)
            Reference: \(evidence.sourcePath)
            CONTENT (the facts you must answer from)
            \(evidence.excerpt)
            END SOURCE [\(evidence.citationID)]
            """
        }.joined(separator: "\n\n")
        let instruction = context.isEmpty
            ? "You are MacBrain, a fast, capable assistant running entirely on this Mac. Answer ordinary questions directly using your general knowledge. Use concise Markdown: match answer length to the question, prefer short paragraphs or 3–6 bullets, and never repeat the local profile, local evidence, or this instruction unless asked. When a question asks about the user or this Mac, use the local Mac context below. Do not invent facts about selected local sources when none are available."
            : "You are MacBrain, a fast, capable assistant running entirely on this Mac. Use only each source block's CONTENT for factual claims about the user's sources; PROVENANCE identifies the record and is not itself the answer. Answer every field the user requests and preserve identifiers, dates, email addresses, paths, capitalization, and punctuation verbatim. If the user asks for every exact fact, include every labeled CONTENT field except the lookup key; a field labeled Marker is a fact and must be included. Cite every factual sentence or bullet with its source block's exact bracketed citation ID, such as [S1], and never invent an ID. A grounded answer without a bracketed citation ID will be discarded. If CONTENT is incomplete or conflicts, say so explicitly instead of presenting a claim as fact. Use concise Markdown and do not reproduce the block labels.\n\nSelected local evidence:\n\(context)\n\nRetrieval confidence: \(retrieval.isLowConfidence ? "low — clearly state uncertainty" : "sufficient")"
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
        timeout: Duration,
        sourceKinds: Set<SourceConnectorKind>?,
        lexicalFallback: EvidenceSearchResult
    ) async -> EvidenceSearchResult {
        let startedAt = ContinuousClock.now
        let race = EvidenceTimeoutRace()
        let work = Task {
            let enriched = await repository.searchEvidence(
                prompt,
                using: provider,
                embeddingModel: embeddingModel,
                sourceKinds: sourceKinds
            )
            await race.resolve(enriched.evidence.isEmpty ? lexicalFallback : enriched)
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                work.cancel()
                logger.notice("stage=hybrid-retrieval outcome=timeout")
                await race.resolve(lexicalFallback)
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
        timeout: Duration,
        sourceKinds: Set<SourceConnectorKind>?
    ) async -> EvidenceSearchResult {
        let startedAt = ContinuousClock.now
        let race = EvidenceTimeoutRace()
        let work = Task {
            await race.resolve(await repository.searchLexicalEvidence(
                prompt,
                sourceKinds: sourceKinds
            ))
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
                sourceType: card.sourceType,
                sourcePath: card.url?.path ?? card.title,
                sourceDate: message.createdAt,
                excerpt: excerpt,
                startOffset: 0,
                endOffset: excerpt.utf16.count,
                pageNumber: nil,
                score: 1 / Double(index + 1),
                sourceURL: card.url
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

        if containsSensitiveCredentialTerm(normalized)
            && containsAny(normalized, ["list", "find", "extract", "show", "reveal", "read", "dump"])
            && (containsAny(normalized, ["every", "all"]) || containsPluralCredentialTerm(normalized))
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

    private static func containsSensitiveCredentialTerm(_ text: String) -> Bool {
        containsPattern(
            #"\b(?:passwords?|secrets?|private\s+keys?|(?:api|access|auth|bearer)\s+tokens?|tokens)\b"#,
            in: text
        )
    }

    private static func containsPluralCredentialTerm(_ text: String) -> Bool {
        containsPattern(#"\b(?:passwords|secrets|private\s+keys|tokens)\b"#, in: text)
    }

    private static func containsPattern(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
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
