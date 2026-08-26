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
        scope: Set<SourceConnectorKind>?,
        lexical: EvidenceSearchResult
    ) -> EvidenceAcceptance {
        guard !lexical.evidence.isEmpty else {
            return EvidenceAcceptance(accepted: false, reason: "no lexical evidence")
        }
        if scope != nil {
            return EvidenceAcceptance(
                accepted: true,
                reason: "explicit source scope with available evidence"
            )
        }
        if hasMatchingDistinctiveIdentifier(prompt: prompt, evidence: lexical.evidence) {
            return EvidenceAcceptance(
                accepted: true,
                reason: "exact distinctive identifier matched"
            )
        }
        if isClearlyPublicKnowledgeRequest(prompt),
           !containsDistinctiveIdentifier(in: prompt) {
            return EvidenceAcceptance(
                accepted: false,
                reason: "public knowledge form has no distinctive local identifier"
            )
        }
        return evaluateImplicit(prompt: prompt, evidence: lexical.evidence)
    }

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
        case .general:
            guard containsDistinctiveIdentifier(in: prompt) else {
                return EvidenceAcceptance(
                    accepted: false,
                    reason: "general request has no distinctive local identifier"
                )
            }
            return evaluateImplicit(prompt: prompt, evidence: lexical.evidence)
        case .casual, .liveMac, .restricted:
            return EvidenceAcceptance(accepted: false, reason: "intent does not permit local evidence")
        }
    }

    private func containsDistinctiveIdentifier(in prompt: String) -> Bool {
        !distinctiveIdentifiers(in: prompt).isEmpty
    }

    private func hasMatchingDistinctiveIdentifier(
        prompt: String,
        evidence: [RetrievalEvidence]
    ) -> Bool {
        let identifiers = distinctiveIdentifiers(in: prompt)
        guard !identifiers.isEmpty else { return false }
        let evidenceText = evidence.map {
            [$0.sourceTitle, $0.sourcePath, $0.excerpt].joined(separator: " ")
        }.joined(separator: " ").lowercased()
        return identifiers.contains { evidenceText.contains($0.lowercased()) }
    }

    private func distinctiveIdentifiers(in text: String) -> [String] {
        let pattern = #"\b(?=[A-Za-z0-9_-]*[A-Za-z])(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)+\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func isClearlyPublicKnowledgeRequest(_ prompt: String) -> Bool {
        let normalized = SourceVocabulary.normalize(prompt).text
        return [
            "what is ", "what are ", "who is ", "who are ", "define ", "explain ",
            "how does ", "how do ", "teach me ", "write ", "translate ",
        ].contains { normalized.hasPrefix($0) }
    }

    private func evaluateImplicit(prompt: String, evidence: [RetrievalEvidence]) -> EvidenceAcceptance {
        if hasMatchingDistinctiveIdentifier(prompt: prompt, evidence: evidence) {
            return EvidenceAcceptance(
                accepted: true,
                reason: "exact distinctive identifier matched"
            )
        }
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
