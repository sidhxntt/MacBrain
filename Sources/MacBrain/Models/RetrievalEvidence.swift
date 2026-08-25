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
