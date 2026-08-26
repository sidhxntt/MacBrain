import Foundation
import Testing
@testable import MacBrain

struct MacBrainDatabaseIndexHealthTests {
    @Test
    func freshDatabaseMigratesIndexHealthAndMetadata() async throws {
        let database = try MacBrainDatabase(url: temporaryDatabaseURL())
        try await database.migrate()

        #expect(await database.schemaVersion == 13)
        #expect(try await database.metadata("legacy_source_import_complete") == nil)
    }

    @Test
    func indexHealthAndMetadataRoundTrip() async throws {
        let url = temporaryDatabaseURL()
        let database = try MacBrainDatabase(url: url)
        let sourceID = UUID()
        let record = ConnectorRecord(
            id: sourceID,
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )
        let timestamp = Date(timeIntervalSince1970: 1_787_750_000)
        let health = ConnectorIndexHealth(
            sourceID: sourceID,
            documentCount: 18,
            chunkCount: 24,
            contentRevision: "notes-r1",
            initialSyncCompleted: true,
            lastSuccessfulSync: timestamp,
            lastVerifiedAt: timestamp,
            lastError: nil
        )

        try await database.save(connectorRecord: record)
        try await database.save(indexHealth: health)
        try await database.setMetadata("legacy_source_import_complete", value: "true")

        let reopened = try MacBrainDatabase(url: url)
        #expect(try await reopened.indexHealth(sourceID: sourceID) == health)
        #expect(try await reopened.allIndexHealth() == [sourceID: health])
        #expect(try await reopened.metadata("legacy_source_import_complete") == "true")
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "macbrain-index-health-tests-" + UUID().uuidString,
                isDirectory: true
            )
            .appendingPathComponent("macbrain.sqlite")
    }
}
