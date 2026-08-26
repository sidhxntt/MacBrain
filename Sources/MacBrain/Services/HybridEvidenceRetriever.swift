import Foundation

actor HybridEvidenceRetriever {
    private let database: MacBrainDatabase
    private let provider: (any InferenceProvider)?
    private let embeddingModel: String
    private let configuration: RetrievalConfiguration

    init(database: MacBrainDatabase, provider: (any InferenceProvider)? = nil, embeddingModel: String = "", configuration: RetrievalConfiguration = .init()) {
        self.database = database
        self.provider = provider
        self.embeddingModel = embeddingModel
        self.configuration = configuration
    }

    func search(
        _ query: String,
        limit: Int = 6,
        sourceIDs: Set<UUID>? = nil
    ) async throws -> EvidenceSearchResult {
        let normalized = query.normalizedRetrievalQuery
        guard !normalized.isEmpty, sourceIDs?.isEmpty != true else { return .empty }
        let candidateLimit = max(limit, configuration.candidateLimit)
        let lexical = try await database.searchChunks(
            matching: normalized,
            limit: candidateLimit,
            matchAllTerms: false,
            sourceIDs: sourceIDs
        )
        let semantic: [StoredChunk]
        do {
            guard let provider else { throw LexicalOnlySearchError() }
            let embeddings = try await provider.embeddings(model: embeddingModel, input: [normalized])
            semantic = try await database.nearestChunks(
                to: embeddings.first?.values ?? [],
                limit: candidateLimit,
                sourceIDs: sourceIDs
            )
        } catch {
            semantic = []
        }

        var candidates = [UUID: Candidate]()
        try await add(lexical, rankWeight: 0.60, to: &candidates)
        try await add(semantic, rankWeight: 0.40, to: &candidates)
        let graph = try await database.graphRelatedChunks(
            to: Array(candidates.keys),
            limit: min(4, candidateLimit),
            sourceIDs: sourceIDs
        )
        try await add(graph, rankWeight: 0.15, to: &candidates)
        return makeResult(from: candidates, limit: limit)
    }

    /// Exact token retrieval used as the activation gate for ambiguous local
    /// questions. This path intentionally performs no embedding request and no
    /// graph expansion.
    func searchLexical(
        _ query: String,
        limit: Int = 6,
        sourceIDs: Set<UUID>? = nil
    ) async throws -> EvidenceSearchResult {
        let normalized = query.normalizedRetrievalQuery
        guard !normalized.isEmpty else { return .empty }
        let candidateLimit = max(limit, configuration.candidateLimit)
        let lexical = try await database.searchChunks(
            matching: normalized,
            limit: candidateLimit,
            matchAllTerms: false,
            sourceIDs: sourceIDs
        )
        var candidates = [UUID: Candidate]()
        try await add(lexical, rankWeight: 1, to: &candidates)
        return makeResult(from: candidates, limit: limit)
    }

    private func makeResult(from candidates: [UUID: Candidate], limit: Int) -> EvidenceSearchResult {
        let selected = candidates.values
            .sorted { $0.score == $1.score ? $0.chunk.startOffset < $1.chunk.startOffset : $0.score > $1.score }
            .reduce(into: [Candidate]()) { selected, candidate in
                guard selected.count < limit else { return }
                guard selected.filter({ $0.source.id == candidate.source.id }).count < configuration.maximumEvidencePerSource else { return }
                guard !selected.contains(where: { $0.chunk.documentID == candidate.chunk.documentID && abs($0.chunk.startOffset - candidate.chunk.startOffset) < 160 }) else { return }
                let excerptLimit = max(1, configuration.contextCharacterBudget / max(limit, 1))
                let currentCharacters = selected.reduce(0) { $0 + min($1.chunk.text.count, excerptLimit) }
                guard currentCharacters + min(candidate.chunk.text.count, excerptLimit) <= configuration.contextCharacterBudget else { return }
                selected.append(candidate)
            }

        let evidence = selected.enumerated().map { index, candidate in
            let location = CitationSourceLocation.resolve(
                sourceType: candidate.source.kind,
                externalID: candidate.document.externalID,
                metadata: candidate.document.metadata
            )
            return RetrievalEvidence(
                citationID: "S\(index + 1)", chunkID: candidate.chunk.id,
                sourceTitle: candidate.document.title, sourceType: candidate.source.kind,
                sourcePath: location.reference,
                sourceDate: candidate.document.modifiedAt ?? candidate.document.createdAt,
                excerpt: String(candidate.chunk.text.prefix(max(1, configuration.contextCharacterBudget / max(limit, 1)))).trimmingCharacters(in: .whitespacesAndNewlines),
                startOffset: candidate.chunk.startOffset,
                endOffset: candidate.chunk.startOffset + min(candidate.chunk.text.utf16.count, max(1, configuration.contextCharacterBudget / max(limit, 1))),
                pageNumber: candidate.chunk.pageNumber,
                score: candidate.score,
                sourceURL: location.url
            )
        }
        return EvidenceSearchResult(evidence: evidence, isLowConfidence: (evidence.first.map(\.score) ?? 0) < configuration.lowConfidenceThreshold)
    }

    private func add(_ chunks: [StoredChunk], rankWeight: Double, to candidates: inout [UUID: Candidate]) async throws {
        for (index, chunk) in chunks.enumerated() {
            guard let document = try await database.document(id: chunk.documentID), let source = try await database.source(id: chunk.sourceID) else { continue }
            let recency = document.modifiedAt ?? document.createdAt
            let ageDays = recency.map { max(0, Date.now.timeIntervalSince($0) / 86_400) } ?? 365
            let score = rankWeight / Double(index + 1) + min(0.08, 30 / (ageDays + 30) * 0.08)
            if let previous = candidates[chunk.id] {
                candidates[chunk.id] = Candidate(chunk: chunk, document: document, source: source, score: previous.score + score)
            } else {
                candidates[chunk.id] = Candidate(chunk: chunk, document: document, source: source, score: score)
            }
        }
    }
}

private struct LexicalOnlySearchError: Error {}

private struct Candidate: Sendable {
    let chunk: StoredChunk
    let document: StoredDocument
    let source: StoredSource
    let score: Double
}

private extension String {
    var normalizedRetrievalQuery: String {
        split { !$0.isLetter && !$0.isNumber }.map(String.init).joined(separator: " ")
    }
}
