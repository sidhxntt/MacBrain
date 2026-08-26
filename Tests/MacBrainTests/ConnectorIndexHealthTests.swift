import Foundation
import Testing
@testable import MacBrain

struct ConnectorIndexHealthTests {
    @Test
    func newConnectorIsNotReady() {
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )

        #expect(record.status == .syncing)
    }

    @Test(arguments: [0, 18])
    func verifiedInitialIndexIsSearchable(documentCount: Int) {
        let now = Date.now
        let health = ConnectorIndexHealth(
            sourceID: UUID(),
            documentCount: documentCount,
            chunkCount: documentCount,
            contentRevision: "revision-1",
            initialSyncCompleted: true,
            lastSuccessfulSync: now,
            lastVerifiedAt: now
        )

        #expect(health.isSearchable)
        #expect(health.isEmpty == (documentCount == 0))
    }

    @Test
    func unverifiedIndexIsNotSearchable() {
        let health = ConnectorIndexHealth(sourceID: UUID())

        #expect(health.isSearchable == false)
        #expect(health.isEmpty == false)
    }
}
