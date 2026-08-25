import Foundation

enum CitationValidator {
    static func hasOnlyKnownCitationIDs(in answer: String, evidence: [RetrievalEvidence]) -> Bool {
        let known = Set(evidence.map(\.citationID))
        return citationIDs(in: answer).isSubset(of: known)
    }

    static func renderedSources(for answer: String, evidence: [RetrievalEvidence]) -> String {
        let used = citationIDs(in: answer)
        let cited = evidence.filter { used.contains($0.citationID) }
        guard !cited.isEmpty else { return "" }
        return "\n\n### Sources\n" + cited.map(render).joined(separator: "\n")
    }

    private static func citationIDs(in text: String) -> Set<String> {
        let pattern = #"\[([A-Za-z]\d+)\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        })
    }

    private static func render(_ evidence: RetrievalEvidence) -> String {
        let location = evidence.pageNumber.map { " (page \($0))" } ?? ""
        if let url = URL(string: evidence.sourcePath), url.scheme != nil {
            return "- [\(evidence.citationID)](\(url.absoluteString)) \(evidence.sourceTitle)\(location)"
        }
        return "- [\(evidence.citationID)](file://\(evidence.sourcePath)) \(evidence.sourceTitle)\(location)"
    }
}
