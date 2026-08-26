import Foundation
import Testing
@testable import MacBrain

@Suite(.serialized)
struct LocalSourceBootstrapTests {
    @Test
    func bootstrapImportsLegacyReadySourceIntoTheSearchDatabase() async throws {
        let fixture = try await LegacySourceFixture.make(documentCount: 18)
        let repository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: fixture.database
        )

        try await repository.bootstrap()

        let matches = try await fixture.database.searchChunks(
            matching: "LEGACY-ORBIT",
            limit: 30
        )
        let health = try #require(await repository.indexHealth(for: fixture.sourceID))
        #expect(matches.count == 18)
        #expect(health.documentCount == 18)
        #expect(health.isSearchable)
        #expect(await repository.record(id: fixture.sourceID)?.status == .ready)
        #expect(await repository.documentCount(for: fixture.sourceID) == 18)
    }

    @Test
    func identicalIncomingDocumentsRepairAnEmptySearchDatabase() async throws {
        let fixture = try await LegacySourceFixture.make(documentCount: 18)
        let repository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: fixture.database
        )
        try await repository.bootstrap()
        try await fixture.database.replaceSourceDocuments(
            sourceID: fixture.sourceID,
            documents: []
        )
        #expect(try await fixture.database.searchChunks(matching: "LEGACY-ORBIT").isEmpty)

        let count = try await repository.replaceDocuments(
            for: fixture.sourceID,
            with: fixture.documents
        )

        let repaired = try await fixture.database.searchChunks(
            matching: "LEGACY-ORBIT",
            limit: 30
        )
        #expect(count == 18)
        #expect(repaired.count == 18)
    }

    @Test
    func secondBootstrapHydratesFromSQLiteAfterLegacyDocumentsAreRetired() async throws {
        let fixture = try await LegacySourceFixture.make(documentCount: 18)
        let firstRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: fixture.database
        )
        try await firstRepository.bootstrap()

        let reopenedDatabase = try MacBrainDatabase(url: fixture.databaseURL)
        let reopenedRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: reopenedDatabase
        )
        try await reopenedRepository.bootstrap()

        #expect(await reopenedRepository.documentCount(for: fixture.sourceID) == 18)
        #expect(try await reopenedDatabase.searchChunks(
            matching: "LEGACY-ORBIT",
            limit: 30
        ).count == 18)
        #expect(try await reopenedDatabase.metadata("legacy_source_import_complete") == "true")
    }

    @Test
    func completedMigrationHydratesFromSQLiteWhenLegacySnapshotIsMissing() async throws {
        let fixture = try await LegacySourceFixture.make(documentCount: 18)
        let firstRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: fixture.database
        )
        try await firstRepository.bootstrap()
        try FileManager.default.removeItem(at: fixture.snapshotURL)

        let reopenedDatabase = try MacBrainDatabase(url: fixture.databaseURL)
        let reopenedRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: reopenedDatabase
        )
        try await reopenedRepository.bootstrap()

        #expect(await reopenedRepository.record(id: fixture.sourceID) != nil)
        #expect(await reopenedRepository.documentCount(for: fixture.sourceID) == 18)
        #expect(await reopenedRepository.verifiedIndexHealth(for: fixture.sourceID)?.isSearchable == true)
        #expect(try await reopenedDatabase.searchChunks(
            matching: "LEGACY-ORBIT",
            limit: 30
        ).count == 18)
    }

    @Test
    func completedMigrationKeepsSQLiteAsTheLiveDocumentAuthority() async throws {
        let fixture = try await LegacySourceFixture.make(documentCount: 18)
        let firstRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: fixture.database
        )
        try await firstRepository.bootstrap()
        try FileManager.default.removeItem(at: fixture.snapshotURL)

        let reopenedDatabase = try MacBrainDatabase(url: fixture.databaseURL)
        let reopenedRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: reopenedDatabase
        )
        try await reopenedRepository.bootstrap()

        let authoritativeDocument = ConnectorDocument(
            connectorID: fixture.sourceID,
            externalID: "sqlite-authority",
            title: "SQLite authority",
            text: "The repository must load this document on demand.",
            sourceLabel: "Apple Notes",
            metadata: ["folder": "Regression"]
        )
        try await reopenedDatabase.replaceSourceDocuments(
            sourceID: fixture.sourceID,
            documents: [StoredDocument(
                id: authoritativeDocument.id,
                sourceID: authoritativeDocument.connectorID,
                externalID: authoritativeDocument.externalID,
                title: authoritativeDocument.title,
                text: authoritativeDocument.text,
                sourceLabel: authoritativeDocument.sourceLabel,
                createdAt: authoritativeDocument.createdAt,
                modifiedAt: authoritativeDocument.modifiedAt,
                metadata: authoritativeDocument.metadata
            )]
        )

        let loadedDocuments = await reopenedRepository.documents(for: fixture.sourceID)
        let reconciledDocuments = try await reopenedRepository.reconciledDocuments(
            for: fixture.sourceID,
            changedDocuments: [],
            presentExternalIDs: [authoritativeDocument.externalID]
        )
        let changedExternalIDs = await reopenedRepository.changedExternalIDs(
            for: fixture.sourceID,
            incoming: [authoritativeDocument]
        )

        #expect(await reopenedRepository.documentCount(for: fixture.sourceID) == 1)
        #expect(loadedDocuments.map(\.externalID) == [authoritativeDocument.externalID])
        #expect(reconciledDocuments.map(\.externalID) == [authoritativeDocument.externalID])
        #expect(changedExternalIDs.isEmpty)
    }

    @Test
    func completedMigrationDoesNotResurrectADeletedSourceFromStaleLegacyJSON() async throws {
        let fixture = try await LegacySourceFixture.make(documentCount: 18)
        let firstRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: fixture.database
        )
        try await firstRepository.bootstrap()
        let staleLegacySnapshot = try Data(contentsOf: fixture.snapshotURL)
        try await firstRepository.remove(id: fixture.sourceID)
        try staleLegacySnapshot.write(to: fixture.snapshotURL, options: .atomic)

        let reopenedDatabase = try MacBrainDatabase(url: fixture.databaseURL)
        let reopenedRepository = LocalSourceRepository(
            fileURL: fixture.snapshotURL,
            database: reopenedDatabase
        )
        try await reopenedRepository.bootstrap()

        #expect(await reopenedRepository.record(id: fixture.sourceID) == nil)
        #expect(await reopenedRepository.allRecords().isEmpty)
        #expect(try await reopenedDatabase.searchChunks(matching: "LEGACY-ORBIT").isEmpty)
    }

    @Test
    func bootstrapRemovesAnExactUnverifiedBrowserProfileDuplicate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-browser-dedup-tests-" + UUID().uuidString,
            isDirectory: true
        )
        let snapshotURL = directory.appendingPathComponent("local-sources.json")
        let databaseURL = directory.appendingPathComponent("macbrain.sqlite")
        let database = try MacBrainDatabase(url: databaseURL)
        let repository = LocalSourceRepository(fileURL: snapshotURL, database: database)
        let configuration = SourceConnectorConfiguration(
            localPath: "/Users/test/Library/Safari",
            browserKind: .safari,
            browserDisplayName: "Safari",
            browserProfileName: "Safari",
            initialSyncCompleted: true
        )
        let stale = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Safari · Safari",
            configuration: configuration,
            status: .ready,
            lastSuccessfulSync: Date(timeIntervalSince1970: 100)
        )
        var verified = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Safari · Safari",
            configuration: configuration,
            status: .ready,
            lastSuccessfulSync: Date(timeIntervalSince1970: 200)
        )
        try await repository.save(stale)
        verified.configuration.initialSyncCompleted = true
        _ = try await repository.commitSourceGeneration(
            record: verified,
            documents: [
                ConnectorDocument(
                    connectorID: verified.id,
                    externalID: "safari-history-1",
                    title: "Verified Safari history",
                    text: "SAFARI-VERIFIED-SURVIVOR",
                    sourceLabel: "Safari · Safari"
                )
            ]
        )
        try await database.setMetadata("legacy_source_import_complete", value: "true")
        #expect(try await database.allConnectorRecords().count == 2)

        let reopenedDatabase = try MacBrainDatabase(url: databaseURL)
        let reopenedRepository = LocalSourceRepository(
            fileURL: snapshotURL,
            database: reopenedDatabase
        )
        try await reopenedRepository.bootstrap()

        let records = await reopenedRepository.allRecords()
        #expect(records.map(\.id) == [verified.id])
        #expect(await reopenedRepository.verifiedIndexHealth(for: verified.id)?.isSearchable == true)
        #expect(try await reopenedDatabase.connectorRecord(id: stale.id) == nil)
        #expect(try await reopenedDatabase.searchChunks(matching: "SAFARI-VERIFIED-SURVIVOR").count == 1)
    }
}

private struct LegacySourceFixture {
    let sourceID: UUID
    let snapshotURL: URL
    let databaseURL: URL
    let database: MacBrainDatabase
    let documents: [ConnectorDocument]

    static func make(documentCount: Int) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-bootstrap-tests-" + UUID().uuidString,
            isDirectory: true
        )
        let snapshotURL = directory.appendingPathComponent("local-sources.json")
        let databaseURL = directory.appendingPathComponent("macbrain.sqlite")
        let sourceID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let record = ConnectorRecord(
            id: sourceID,
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: timestamp,
            documentCount: documentCount
        )
        let documents = (0..<documentCount).map { index in
            ConnectorDocument(
                connectorID: sourceID,
                externalID: "legacy-note-\(index)",
                title: "Legacy note \(index)",
                text: "LEGACY-ORBIT searchable note \(index)",
                sourceLabel: "Apple Notes",
                modifiedAt: timestamp.addingTimeInterval(Double(index))
            )
        }
        let legacyRepository = LocalSourceRepository(fileURL: snapshotURL)
        try await legacyRepository.save(record)
        _ = try await legacyRepository.replaceDocuments(for: sourceID, with: documents)

        return Self(
            sourceID: sourceID,
            snapshotURL: snapshotURL,
            databaseURL: databaseURL,
            database: try MacBrainDatabase(url: databaseURL),
            documents: documents
        )
    }
}
