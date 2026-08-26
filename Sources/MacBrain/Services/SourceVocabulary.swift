import Foundation

struct NormalizedSourcePrompt: Equatable, Sendable {
    let text: String
    let paddedText: String
    let tokens: [String]

    func containsPhrase(_ phrase: String) -> Bool {
        paddedText.contains(" \(SourceVocabulary.normalize(phrase).text) ")
    }

    func containsAnyPhrase(_ phrases: [String]) -> Bool {
        phrases.contains(where: containsPhrase)
    }
}

struct SourceVocabulary: Sendable {
    private let records: [ConnectorRecord]

    init(records: [ConnectorRecord] = []) {
        self.records = records
    }

    func scope(in prompt: String) -> Set<SourceConnectorKind>? {
        let normalized = Self.normalize(prompt)
        var kinds = Set<SourceConnectorKind>()

        for (kind, phrases) in Self.phrasesByKind where normalized.containsAnyPhrase(phrases) {
            kinds.insert(kind)
        }
        for record in records {
            let displayName = Self.normalize(record.displayName).text
            guard displayName.count >= 3,
                  normalized.paddedText.contains(" \(displayName) ") else {
                continue
            }
            kinds.insert(record.kind)
        }
        return kinds.isEmpty ? nil : kinds
    }

    static func normalize(_ prompt: String) -> NormalizedSourcePrompt {
        let tokens = prompt
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let text = tokens.joined(separator: " ")
        return NormalizedSourcePrompt(
            text: text,
            paddedText: " \(text) ",
            tokens: tokens
        )
    }

    /// Resolves first-person inventory questions without turning generic nouns
    /// such as “photos” into an always-local retrieval signal.
    static func firstPersonCountScope(in prompt: NormalizedSourcePrompt) -> Set<SourceConnectorKind>? {
        guard prompt.containsAnyPhrase([
            "how many", "total number", "number of", "count", "item count"
        ]),
        !Set(prompt.tokens).isDisjoint(with: ["i", "my", "we", "our"]) else {
            return nil
        }

        let kinds = Set(Self.countNounsByKind.compactMap { kind, nouns in
            prompt.containsAnyPhrase(nouns) ? kind : nil
        })
        return kinds.isEmpty ? nil : kinds
    }

    private static let phrasesByKind: [SourceConnectorKind: [String]] = [
        .appleNotes: [
            "apple notes", "my note", "my notes", "connected notes", "notes"
        ],
        .appleMail: [
            "apple mail", "my mail", "my email", "my emails", "connected mail",
            "emails", "notes and mail", "and mail"
        ],
        .calendar: [
            "apple calendar", "my calendar", "my work calendar", "connected calendar",
            "calendar event", "calendar events", "calendar meeting"
        ],
        .reminders: [
            "apple reminders", "my reminders", "connected reminders", "reminders"
        ],
        .contacts: [
            "apple contacts", "my contacts", "connected contacts", "contacts"
        ],
        .browserProfile: [
            "my browser", "browser profile", "browser history", "my bookmarks",
            "my reading list", "my open tabs", "my downloads"
        ],
        .messages: [
            "apple messages", "my messages", "in messages", "imessage"
        ],
        .photos: [
            "apple photos", "my photos", "photos metadata"
        ],
        .books: [
            "apple books", "my books", "books library"
        ],
        .folder: [
            "my folder", "connected folder", "test folder", "my files", "my documents"
        ],
        .gitRepository: [
            "git repository", "git repo", "my repository", "my repo",
            "this repository", "this repo", "this git repository", "this git repo"
        ],
    ]

    private static let countNounsByKind: [SourceConnectorKind: [String]] = [
        .appleNotes: ["note", "notes"],
        .appleMail: ["email", "emails", "mail"],
        .calendar: ["event", "events", "meeting", "meetings"],
        .reminders: ["reminder", "reminders"],
        .contacts: ["contact", "contacts"],
        .browserProfile: ["browser item", "browser items", "bookmark", "bookmarks"],
        .messages: ["message", "messages", "imessage", "imessages"],
        .photos: ["photo", "photos"],
        .books: ["book", "books"],
        .folder: ["file", "files", "document", "documents"],
        .gitRepository: ["repository item", "repository items"],
    ]
}
