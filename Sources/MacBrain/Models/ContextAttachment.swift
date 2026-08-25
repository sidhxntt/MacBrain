import Foundation

enum ContextAttachmentKind: String, CaseIterable, Identifiable, Sendable, Equatable {
    case selectedText
    case clipboard
    case activeWindow
    case repository

    var id: String { rawValue }
    var title: String {
        switch self {
        case .selectedText: "Selected text"
        case .clipboard: "Clipboard"
        case .activeWindow: "Active app"
        case .repository: "Repository"
        }
    }

    var expiresAfterRequest: Bool { self == .selectedText || self == .clipboard }
}

struct ContextAttachment: Identifiable, Sendable, Equatable {
    static let maximumCharacters = 2_000
    let kind: ContextAttachmentKind
    let value: String
    var id: ContextAttachmentKind { kind }

    var preview: String { String(value.prefix(Self.maximumCharacters)) }
    var promptLine: String { "\(kind.title): \(preview)" }
}

struct PromptBudgetPolicy: Sendable {
    let maximumContextCharacters: Int
    let maximumHistoryMessages: Int

    init(maximumContextCharacters: Int = 8_000, maximumHistoryMessages: Int = 8) {
        self.maximumContextCharacters = maximumContextCharacters
        self.maximumHistoryMessages = maximumHistoryMessages
    }

    func boundedContext(_ attachments: [ContextAttachment]) -> String {
        String(attachments.map(\.promptLine).joined(separator: "\n").prefix(maximumContextCharacters))
    }

    func boundedHistory(_ history: [ChatMessage]) -> [ChatMessage] {
        Array(history.suffix(maximumHistoryMessages))
    }
}
