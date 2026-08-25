import Foundation

enum ChatHoverPreviewPolicy {
    static let titleCharacterLimit = 36

    static func shouldShowPreview(for title: String) -> Bool {
        true
    }

    static func shouldAutoScrollTitle(for title: String) -> Bool {
        title.count > titleCharacterLimit
    }

    static func previewText(for session: ChatSession) -> String {
        let text = session.messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? String(text!.prefix(180)) : "New local conversation"
    }
}
