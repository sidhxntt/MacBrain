import Foundation

struct ChatCitationCard: Identifiable, Equatable, Sendable {
    let citationID: String
    let title: String
    let sourceType: String
    let url: URL?

    var id: String { citationID }
    var sourceTypeDisplayName: String {
        SourceConnectorKind(rawValue: sourceType)?.displayName ?? sourceType
    }

    static func parse(from response: String) -> [Self] {
        guard let sourcesHeader = response.range(of: "### Sources", options: .backwards) else {
            return []
        }
        let sourcesSection = String(response[sourcesHeader.lowerBound...])
        let typedPattern = #"^- \[([A-Za-z]\d+)\](?:\((.+)\))?\s+\[([A-Za-z][A-Za-z0-9-]*)\]\s+(.+)$"#
        let legacyFilePattern = #"^- \[([A-Za-z]\d+)\]\((file://[^)]+)\)\s+(?!\[)(.+)$"#
        let typed = matches(pattern: typedPattern, in: sourcesSection, sourceTypeGroup: 3, titleGroup: 4)
        let legacy = matches(pattern: legacyFilePattern, in: sourcesSection, sourceTypeGroup: nil, titleGroup: 3)
        return (typed + legacy).sorted { $0.location < $1.location }.map(\.card)
    }

    private static func matches(
        pattern: String,
        in response: String,
        sourceTypeGroup: Int?,
        titleGroup: Int
    ) -> [(location: Int, card: Self)] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        ) else { return [] }
        let range = NSRange(response.startIndex..., in: response)
        return expression.matches(in: response, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: response),
                  let titleRange = Range(match.range(at: titleGroup), in: response) else { return nil }
            let sourceType = sourceTypeGroup
                .flatMap { Range(match.range(at: $0), in: response) }
                .map { String(response[$0]) } ?? "local"
            let url = Range(match.range(at: 2), in: response)
                .flatMap { safeURL(String(response[$0])) }
            return (
                match.range.location,
                Self(
                    citationID: String(response[idRange]),
                    title: String(response[titleRange]),
                    sourceType: sourceType,
                    url: url
                )
            )
        }
    }

    private static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return nil }
        if url.isFileURL {
            return (url.path as NSString).isAbsolutePath ? url : nil
        }
        return ["http", "https"].contains(scheme) && url.host != nil ? url : nil
    }
}
