import Foundation

struct ConnectorQueryService: Sendable {
    let repository: LocalSourceRepository
    private let now: @Sendable () -> Date

    init(
        repository: LocalSourceRepository,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.now = now
    }

    func response(
        for operation: ConnectorQueryOperation,
        scope: Set<SourceConnectorKind>?
    ) async -> String {
        let execution = await repository.executeConnectorQuery(
            operation,
            scope: scope,
            now: now()
        )
        switch execution {
        case .result(let result, let sourceKinds):
            return Self.render(result, sourceKinds: sourceKinds)
        case .notConnected(let requestedKinds):
            if requestedKinds.isEmpty {
                return "No searchable connector is connected yet. Connect a source, then let its first index finish."
            }
            return "\(Self.kindList(requestedKinds)) isn’t connected. Connect it in Sources first."
        case .permissionNeeded(let sourceKinds):
            return "\(Self.kindList(sourceKinds)) needs permission and is not searchable until access is restored."
        case .indexUnavailable(let sourceKinds):
            return "\(Self.kindList(sourceKinds)) is still building its first searchable index. I can answer after that index is verified."
        case .failed(let message):
            return "I couldn’t read the verified local index: \(message)"
        }
    }

    private static func render(
        _ result: ConnectorQueryResult,
        sourceKinds: Set<SourceConnectorKind>
    ) -> String {
        switch result.operation {
        case .count:
            return renderCount(result.totalCount ?? 0, sourceKinds: sourceKinds)
        case .newest:
            return renderDocuments(
                result.documents,
                emptyDescription: "The verified index has no matching items.",
                dateLabel: "Modified",
                metadataDateKey: nil
            )
        case .oldest:
            return renderDocuments(
                result.documents,
                emptyDescription: "The verified index has no matching items.",
                dateLabel: "Modified",
                metadataDateKey: nil
            )
        case .nextEvent:
            return renderDocuments(
                result.documents,
                emptyDescription: "The verified Calendar index has no future event.",
                dateLabel: "Starts",
                metadataDateKey: "start"
            )
        case .firstDueReminder:
            return renderDocuments(
                result.documents,
                emptyDescription: "The verified Reminders index has no incomplete reminder with a due date.",
                dateLabel: "Due",
                metadataDateKey: "due"
            )
        }
    }

    private static func renderCount(
        _ count: Int,
        sourceKinds: Set<SourceConnectorKind>
    ) -> String {
        if sourceKinds.count == 1, let kind = sourceKinds.first {
            let noun = count == 1 ? singularNoun(for: kind) : pluralNoun(for: kind)
            if count == 0 {
                return "\(kind.displayName) has a verified searchable index with 0 \(noun)."
            }
            return "There are \(count) \(noun) in the verified \(kind.displayName) index."
        }
        return "There are \(count) indexed items across \(kindList(sourceKinds))."
    }

    private static func renderDocuments(
        _ documents: [ConnectorDocument],
        emptyDescription: String,
        dateLabel: String,
        metadataDateKey: String?
    ) -> String {
        guard !documents.isEmpty else { return emptyDescription }
        return documents.map { document in
            let date: Date?
            if let metadataDateKey,
               let value = document.metadata[metadataDateKey] {
                date = try? Date(value, strategy: .iso8601)
            } else {
                date = document.modifiedAt ?? document.createdAt
            }
            let dateText = date?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"
            return "\(document.title) — \(document.sourceLabel) — \(dateLabel): \(dateText)"
        }.joined(separator: "\n")
    }

    private static func kindList(_ kinds: Set<SourceConnectorKind>) -> String {
        let names = kinds.map(\.displayName).sorted()
        switch names.count {
        case 0: return "That source"
        case 1: return names[0]
        case 2: return names.joined(separator: " and ")
        default: return names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
    }

    private static func singularNoun(for kind: SourceConnectorKind) -> String {
        switch kind {
        case .appleNotes: "note"
        case .appleMail: "email"
        case .calendar: "event"
        case .reminders: "reminder"
        case .contacts: "contact"
        case .browserProfile: "browser item"
        case .messages: "message"
        case .photos: "photo"
        case .books: "book"
        case .folder: "file"
        case .gitRepository: "repository item"
        }
    }

    private static func pluralNoun(for kind: SourceConnectorKind) -> String {
        switch kind {
        case .appleNotes: "notes"
        case .appleMail: "emails"
        case .calendar: "events"
        case .reminders: "reminders"
        case .contacts: "contacts"
        case .browserProfile: "browser items"
        case .messages: "messages"
        case .photos: "photos"
        case .books: "books"
        case .folder: "files"
        case .gitRepository: "repository items"
        }
    }
}
