import Foundation

struct EvidenceAcceptance: Equatable, Sendable {
    let accepted: Bool
    let reason: String
}

/// Applies an absolute lexical relevance threshold before an ambiguous prompt
/// is allowed to activate local retrieval. Retriever rank alone is deliberately
/// insufficient because even an unrelated result is always ranked "first."
struct EvidenceAcceptancePolicy: Sendable {
    func evaluate(
        prompt: String,
        intent: ChatQueryIntent,
        lexical: EvidenceSearchResult
    ) -> EvidenceAcceptance {
        guard !lexical.evidence.isEmpty else {
            return EvidenceAcceptance(accepted: false, reason: "no lexical evidence")
        }

        switch intent {
        case .explicitLocal:
            return EvidenceAcceptance(accepted: true, reason: "explicit local request with available evidence")
        case .implicitLocal:
            return evaluateImplicit(prompt: prompt, evidence: lexical.evidence)
        case .casual, .general, .liveMac, .restricted:
            return EvidenceAcceptance(accepted: false, reason: "intent does not permit local evidence")
        }
    }

    private func evaluateImplicit(prompt: String, evidence: [RetrievalEvidence]) -> EvidenceAcceptance {
        let queryTokens = contentTokens(in: prompt)
        guard !queryTokens.isEmpty else {
            return EvidenceAcceptance(accepted: false, reason: "no significant query terms")
        }

        let evidenceText = evidence.map {
            [$0.sourceTitle, $0.sourcePath, $0.excerpt].joined(separator: " ")
        }.joined(separator: " ")
        let evidenceTokens = Set(contentTokens(in: evidenceText))
        let overlap = Set(queryTokens).intersection(evidenceTokens)
        let distinctiveOverlap = overlap.filter {
            $0.count >= 4 && !Self.genericInternalTerms.contains($0)
        }

        if !distinctiveOverlap.isEmpty && overlap.count >= 2 {
            return EvidenceAcceptance(accepted: true, reason: "distinctive entity and supporting term matched")
        }
        if distinctiveOverlap.contains(where: { $0.count >= 7 }) {
            return EvidenceAcceptance(accepted: true, reason: "distinctive entity matched")
        }
        if containsSignificantPhrase(queryTokens: queryTokens, in: evidenceText) {
            return EvidenceAcceptance(accepted: true, reason: "significant lexical phrase matched")
        }

        return EvidenceAcceptance(accepted: false, reason: "lexical overlap below absolute threshold")
    }

    private func containsSignificantPhrase(queryTokens: [String], in evidenceText: String) -> Bool {
        guard queryTokens.count >= 2 else { return false }
        let normalizedEvidence = contentTokens(in: evidenceText).joined(separator: " ")
        for index in 0..<(queryTokens.count - 1) {
            let first = queryTokens[index]
            let second = queryTokens[index + 1]
            guard first.count + second.count >= 11 else { continue }
            if normalizedEvidence.contains("\(first) \(second)") {
                return true
            }
        }
        return false
    }

    private func contentTokens(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !Self.stopWords.contains($0) }
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "did", "do", "does", "for",
        "from", "give", "how", "i", "in", "is", "it", "me", "my", "of", "on", "our",
        "the", "this", "to", "was", "we", "were", "what", "when", "where", "which", "who",
        "why", "with", "you"
    ]

    private static let genericInternalTerms: Set<String> = [
        "action", "approved", "attended", "beta", "blockers", "changed", "codename", "customer",
        "date", "deadline", "decision", "design", "document", "handoff", "index", "internal",
        "launch", "local", "make", "migration", "owner", "owns", "plan", "planning", "project",
        "recorded", "release", "review", "rollback", "ship", "status", "summary", "team", "target",
        "upcoming"
    ]
}
