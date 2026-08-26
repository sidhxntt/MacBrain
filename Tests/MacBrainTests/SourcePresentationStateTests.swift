import Foundation
import Testing
@testable import MacBrain

struct SourcePresentationStateTests {
    @Test
    func readyRecordWithoutVerifiedHealthIsNotPresentedAsSearchable() {
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(),
            status: .ready,
            documentCount: 18
        )

        #expect(ConnectorPresentationState(record: record, health: nil) == .connecting)
    }

    @Test
    func verifiedEmptyAndNonemptySourcesHaveDistinctReadyStates() {
        let sourceID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let record = ConnectorRecord(
            id: sourceID,
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: timestamp
        )
        let empty = ConnectorIndexHealth(
            sourceID: sourceID,
            documentCount: 0,
            chunkCount: 0,
            contentRevision: "empty",
            initialSyncCompleted: true,
            lastSuccessfulSync: timestamp,
            lastVerifiedAt: timestamp
        )
        let populated = ConnectorIndexHealth(
            sourceID: sourceID,
            documentCount: 18,
            chunkCount: 18,
            contentRevision: "populated",
            initialSyncCompleted: true,
            lastSuccessfulSync: timestamp,
            lastVerifiedAt: timestamp
        )

        #expect(
            ConnectorPresentationState(record: record, health: empty)
                == .empty(lastSuccessfulSync: timestamp)
        )
        #expect(
            ConnectorPresentationState(record: record, health: populated)
                == .ready(documentCount: 18, lastSuccessfulSync: timestamp)
        )
    }

    @Test
    func backgroundRefreshKeepsVerifiedIndexAvailable() {
        let sourceID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let record = ConnectorRecord(
            id: sourceID,
            kind: .calendar,
            displayName: "Apple Calendar",
            configuration: .init(initialSyncCompleted: true),
            status: .syncing,
            lastSuccessfulSync: timestamp,
            documentCount: 9
        )
        let health = ConnectorIndexHealth(
            sourceID: sourceID,
            documentCount: 9,
            chunkCount: 9,
            contentRevision: "r1",
            initialSyncCompleted: true,
            lastSuccessfulSync: timestamp,
            lastVerifiedAt: timestamp
        )

        #expect(
            ConnectorPresentationState(record: record, health: health)
                == .refreshing(documentCount: 9, lastSuccessfulSync: timestamp)
        )
    }

    @Test
    func failedRefreshReportsWhetherAQueryableIndexWasRetained() {
        let sourceID = UUID()
        var record = ConnectorRecord(
            id: sourceID,
            kind: .contacts,
            displayName: "Apple Contacts",
            configuration: .init(),
            status: .failed,
            lastError: "Controlled failure"
        )
        #expect(
            ConnectorPresentationState(record: record, health: nil)
                == .failed(documentCount: 0, hasSearchableIndex: false)
        )

        let health = ConnectorIndexHealth(
            sourceID: sourceID,
            documentCount: 12,
            chunkCount: 12,
            contentRevision: "r1",
            initialSyncCompleted: true,
            lastSuccessfulSync: .now,
            lastVerifiedAt: .now
        )
        record.documentCount = 999
        #expect(
            ConnectorPresentationState(record: record, health: health)
                == .failed(documentCount: 12, hasSearchableIndex: true)
        )
    }
}
