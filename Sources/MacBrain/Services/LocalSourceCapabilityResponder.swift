import Foundation

enum LocalSourceCapabilityResponder {
    static func response(
        for prompt: String,
        records: [ConnectorRecord],
        healthBySourceID: [UUID: ConnectorIndexHealth] = [:]
    ) -> String? {
        guard isDirectCapabilityQuestion(prompt),
              let kinds = SourceQueryScope.resolve(prompt: prompt)
        else {
            return nil
        }

        return response(
            for: kinds,
            records: records,
            healthBySourceID: healthBySourceID
        )
    }

    static func response(
        for kinds: Set<SourceConnectorKind>,
        records: [ConnectorRecord],
        healthBySourceID: [UUID: ConnectorIndexHealth] = [:]
    ) -> String {
        return kinds
            .sorted { $0.rawValue < $1.rawValue }
            .map {
                statusMessage(
                    for: $0,
                    records: records,
                    healthBySourceID: healthBySourceID
                )
            }
            .joined(separator: "\n\n")
    }

    private static func isDirectCapabilityQuestion(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .joined(separator: " ")

        let capabilityPhrases = [
            "can you read",
            "can you access",
            "do you have access",
            "are my",
            "is my",
        ]
        guard capabilityPhrases.contains(where: { normalized.hasPrefix($0) }) else {
            return false
        }

        let contentOperations = [
            "search", "find", "summarize", "show", "tell", "about", "what", "who",
            "when", "where", "why", "how",
        ]
        return contentOperations.contains { normalized.contains(" \($0) ") } == false
    }

    private static func statusMessage(
        for kind: SourceConnectorKind,
        records: [ConnectorRecord],
        healthBySourceID: [UUID: ConnectorIndexHealth]
    ) -> String {
        let matching = records.filter { $0.kind == kind }
        guard matching.isEmpty == false else {
            return "\(kind.displayName) isn’t connected yet. Add it in Sources, then connect and authorize it so I can search it locally."
        }

        let states = matching.map { record in
            ConnectorPresentationState(
                record: record,
                health: healthBySourceID[record.id]
            )
        }

        if states.contains(where: { state in
            if case .ready = state { return true }
            return false
        }) {
            return "Yes — \(kind.displayName) is connected locally and ready to search."
        }
        if let documentCount = states.compactMap({ state -> Int? in
            guard case .refreshing(let documentCount, _) = state else { return nil }
            return documentCount
        }).first {
            return "\(kind.displayName) is connected and refreshing. Its \(itemCount(documentCount)) verified index remains searchable while the latest changes sync."
        }
        if states.contains(where: { state in
            if case .empty = state { return true }
            return false
        }) {
            return "Yes — \(kind.displayName) is connected and synced, but its searchable index is empty."
        }
        if states.contains(where: { state in
            if case .connecting = state { return true }
            if case .syncing = state { return true }
            return false
        }) {
            return "\(kind.displayName) is connected, but its first searchable index is still being prepared. It isn’t ready to search yet."
        }
        if let state = states.first(where: { state in
            if case .needsAuthorization = state { return true }
            return false
        }), case .needsAuthorization(let documentCount, let hasSearchableIndex) = state {
            if hasSearchableIndex {
                return "\(kind.displayName) needs macOS permission. Its last verified \(itemCount(documentCount)) index is retained locally but unavailable until you reauthorize it in Sources."
            }
            return "\(kind.displayName) is connected, but macOS permission is needed before I can read it. Reauthorize it in Sources."
        }
        if let state = states.first(where: { state in
            if case .paused = state { return true }
            return false
        }), case .paused(let documentCount, let hasSearchableIndex) = state {
            if hasSearchableIndex {
                return "\(kind.displayName) is paused. Its \(itemCount(documentCount)) verified index remains searchable; resume it to include new changes."
            }
            return "\(kind.displayName) is connected but paused and has no verified searchable index yet."
        }
        if let state = states.first(where: { state in
            if case .failed = state { return true }
            return false
        }), case .failed(let documentCount, let hasSearchableIndex) = state {
            if hasSearchableIndex {
                return "The latest \(kind.displayName) sync failed, but its \(itemCount(documentCount)) verified index remains searchable. Check Sources and retry."
            }
            return "\(kind.displayName) is connected, but its sync failed before a searchable index was verified. Check Sources and retry."
        }
        return "\(kind.displayName) is connected, but it is not ready to search yet."
    }

    private static func itemCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "item" : "items")"
    }
}
