import Foundation

enum SourceSyncActivityState: Equatable, Sendable {
    case syncing
    case completed
    case needsAttention

    var symbolName: String {
        switch self {
        case .syncing: "arrow.triangle.2.circlepath"
        case .completed: "checkmark.circle"
        case .needsAttention: "exclamationmark.triangle"
        }
    }
}

struct SourceSyncActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceID: UUID
    let sourceName: String
    let state: SourceSyncActivityState
    let detail: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        sourceID: UUID,
        sourceName: String,
        state: SourceSyncActivityState,
        detail: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.state = state
        self.detail = detail
        self.timestamp = timestamp
    }
}

struct SourceSyncActivityGroup: Identifiable, Equatable, Sendable {
    let sourceID: UUID
    let sourceName: String
    let activities: [SourceSyncActivity]

    var id: UUID { sourceID }
    var latestActivity: SourceSyncActivity { activities[0] }
}

extension Array where Element == SourceSyncActivity {
    func groupedBySource() -> [SourceSyncActivityGroup] {
        Dictionary(grouping: self, by: \.sourceID)
            .map { sourceID, activities in
                let orderedActivities = activities.sorted { $0.timestamp > $1.timestamp }
                return SourceSyncActivityGroup(
                    sourceID: sourceID,
                    sourceName: orderedActivities[0].sourceName,
                    activities: orderedActivities
                )
            }
            .sorted { $0.latestActivity.timestamp > $1.latestActivity.timestamp }
    }
}
