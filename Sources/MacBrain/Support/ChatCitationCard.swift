import Foundation

struct ChatCitationCard: Identifiable, Equatable, Sendable {
    let citationID: String
    let title: String
    let url: URL

    var id: String { citationID }

    static func parse(from response: String) -> [Self] {
        let pattern = #"^- \[([A-Za-z]\d+)\]\((file://[^)]+)\)\s+(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(response.startIndex..., in: response)
        return expression.matches(in: response, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: response),
                  let urlRange = Range(match.range(at: 2), in: response),
                  let titleRange = Range(match.range(at: 3), in: response),
                  let url = URL(string: String(response[urlRange])),
                  url.isFileURL else { return nil }
            return Self(citationID: String(response[idRange]), title: String(response[titleRange]), url: url)
        }
    }
}
