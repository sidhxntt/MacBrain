import Foundation

enum ChatTitleGenerator {
    static func title(for prompt: String) -> String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? prompt
        let normalized = firstLine
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard normalized.count > 48 else { return normalized }
        return String(normalized.prefix(47)) + "…"
    }
}
