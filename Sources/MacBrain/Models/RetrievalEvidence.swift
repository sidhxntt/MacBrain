import Foundation

struct RetrievalEvidence: Codable, Equatable, Identifiable, Sendable {
    var id: String { citationID }
    let citationID: String
    let chunkID: UUID
    let sourceTitle: String
    let sourceType: String
    let sourcePath: String
    let sourceDate: Date?
    let excerpt: String
    let startOffset: Int
    let endOffset: Int
    let pageNumber: Int?
    let score: Double
    let sourceURL: URL?

    init(
        citationID: String,
        chunkID: UUID,
        sourceTitle: String,
        sourceType: String,
        sourcePath: String,
        sourceDate: Date?,
        excerpt: String,
        startOffset: Int,
        endOffset: Int,
        pageNumber: Int?,
        score: Double,
        sourceURL: URL? = nil
    ) {
        self.citationID = citationID
        self.chunkID = chunkID
        self.sourceTitle = sourceTitle
        self.sourceType = sourceType
        self.sourcePath = sourcePath
        self.sourceDate = sourceDate
        self.excerpt = excerpt
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.pageNumber = pageNumber
        self.score = score
        self.sourceURL = sourceURL
    }
}

struct EvidenceSearchResult: Equatable, Sendable {
    let evidence: [RetrievalEvidence]
    let isLowConfidence: Bool

    static let empty = Self(evidence: [], isLowConfidence: true)
}

struct RetrievalConfiguration: Sendable, Equatable {
    var candidateLimit: Int
    var contextCharacterBudget: Int
    var maximumEvidencePerSource: Int
    var lowConfidenceThreshold: Double

    init(candidateLimit: Int = 16, contextCharacterBudget: Int = 6_000, maximumEvidencePerSource: Int = 2, lowConfidenceThreshold: Double = 0.35) {
        self.candidateLimit = candidateLimit
        self.contextCharacterBudget = contextCharacterBudget
        self.maximumEvidencePerSource = maximumEvidencePerSource
        self.lowConfidenceThreshold = lowConfidenceThreshold
    }
}
