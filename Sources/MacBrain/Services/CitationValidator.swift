import Foundation

enum CitationValidator {
    static func hasOnlyKnownCitationIDs(in answer: String, evidence: [RetrievalEvidence]) -> Bool {
        let known = Set(evidence.map(\.citationID))
        return citationIDs(in: answer).isSubset(of: known)
    }

    static func hasValidCitation(in answer: String, evidence: [RetrievalEvidence]) -> Bool {
        let used = citationIDs(in: answer)
        return !used.isEmpty && used.isSubset(of: Set(evidence.map(\.citationID)))
    }

    static func citesEveryRetrievedSource(in answer: String, evidence: [RetrievalEvidence]) -> Bool {
        let used = citationIDs(in: answer)
        let citedSources = Set(evidence.filter { used.contains($0.citationID) }.map(\.sourcePath))
        let retrievedSources = Set(evidence.map(\.sourcePath))
        return !retrievedSources.isEmpty && citedSources == retrievedSources
    }

    static func renderedSources(for answer: String, evidence: [RetrievalEvidence]) -> String {
        let used = citationIDs(in: answer)
        return renderedSources(for: evidence.filter { used.contains($0.citationID) })
    }

    static func renderedSources(for evidence: [RetrievalEvidence]) -> String {
        guard !evidence.isEmpty else { return "" }
        return "### Sources\n" + evidence.map(render).joined(separator: "\n") + "\n\n"
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
        let sourceType = evidence.sourceType
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let sourceTitle = evidence.sourceTitle
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if let url = evidence.sourceURL.flatMap(safeDestination) ?? legacySafeURL(for: evidence) {
            return "- [\(evidence.citationID)](\(url.absoluteString)) [\(sourceType)] \(sourceTitle)\(location)"
        }
        return "- [\(evidence.citationID)] [\(sourceType)] \(sourceTitle)\(location)"
    }

    private static func legacySafeURL(for evidence: RetrievalEvidence) -> URL? {
        if let url = URL(string: evidence.sourcePath),
           let scheme = url.scheme?.lowercased(),
           ["file", "http", "https"].contains(scheme) {
            return safeDestination(url)
        }
        if [SourceConnectorKind.folder.rawValue, SourceConnectorKind.gitRepository.rawValue]
            .contains(evidence.sourceType),
           evidence.sourcePath.hasPrefix("/") {
            return URL(fileURLWithPath: evidence.sourcePath)
        }
        return nil
    }

    private static func safeDestination(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        if url.isFileURL {
            return (url.path as NSString).isAbsolutePath ? url : nil
        }
        return ["http", "https"].contains(scheme) && url.host != nil ? url : nil
    }
}
