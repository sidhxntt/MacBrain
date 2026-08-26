import Foundation
import Testing
@testable import MacBrain

@Suite(.serialized)
struct SourceIndexCommitTests {
    @Test
    func successfulGenerationPersistsVerifiedCountsAndSearchIndex() async throws {
        let fixture = try SourceCommitFixture()
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let record = fixture.record(status: .ready, timestamp: timestamp)
        let documents = [
            fixture.document(externalID: "note-1", marker: "FIRST-VERIFIED"),
            fixture.document(externalID: "note-2", marker: "SECOND-VERIFIED")
        ]

        let committed = try await fixture.database.commitSourceGeneration(
            record: record,
            documents: documents,
            health: fixture.health(revision: "r1", timestamp: timestamp)
        )

        #expect(committed.documentCount == 2)
        #expect(committed.chunkCount >= 2)
        #expect(committed.isSearchable)
        #expect(try await fixture.database.indexHealth(sourceID: fixture.sourceID) == committed)
        let storedRecord = try #require(await fixture.database.connectorRecord(id: fixture.sourceID))
        #expect(storedRecord.status == .ready)
        #expect(storedRecord.documentCount == 2)
        #expect(try await fixture.database.searchChunks(matching: "FIRST-VERIFIED").count == 1)
        #expect(try await fixture.database.searchChunks(matching: "SECOND-VERIFIED").count == 1)
    }

    @Test
    func emptyGenerationIsVerifiedAndRemovesPreviousSearchRows() async throws {
        let fixture = try SourceCommitFixture()
        let firstTimestamp = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try await fixture.database.commitSourceGeneration(
            record: fixture.record(status: .ready, timestamp: firstTimestamp),
            documents: [fixture.document(externalID: "old", marker: "OLD-CONTENT")],
            health: fixture.health(revision: "r1", timestamp: firstTimestamp)
        )

        let secondTimestamp = firstTimestamp.addingTimeInterval(300)
        let committed = try await fixture.database.commitSourceGeneration(
            record: fixture.record(status: .ready, timestamp: secondTimestamp),
            documents: [],
            health: fixture.health(revision: "r2", timestamp: secondTimestamp)
        )

        #expect(committed.documentCount == 0)
        #expect(committed.chunkCount == 0)
        #expect(committed.isSearchable)
        #expect(committed.isEmpty)
        #expect(try await fixture.database.searchChunks(matching: "OLD-CONTENT").isEmpty)
        #expect(try await fixture.database.connectorRecord(id: fixture.sourceID)?.documentCount == 0)
    }

    @Test
    func failedGenerationKeepsPreviousVerifiedIndexAndConnectorState() async throws {
        let fixture = try SourceCommitFixture()
        let firstTimestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let originalRecord = fixture.record(status: .ready, timestamp: firstTimestamp)
        _ = try await fixture.database.commitSourceGeneration(
            record: originalRecord,
            documents: [fixture.document(externalID: "old", marker: "OLD-VERIFIED")],
            health: fixture.health(revision: "r1", timestamp: firstTimestamp)
        )
        let previouslyCommittedRecord = try #require(
            await fixture.database.connectorRecord(id: fixture.sourceID)
        )

        let secondTimestamp = firstTimestamp.addingTimeInterval(300)
        var uncommittedRecord = fixture.record(status: .ready, timestamp: secondTimestamp)
        uncommittedRecord.displayName = "Uncommitted name"
        do {
            _ = try await fixture.database.commitSourceGeneration(
                record: uncommittedRecord,
                documents: [fixture.document(externalID: "new", marker: "NEW-UNCOMMITTED")],
                health: fixture.health(revision: "r2", timestamp: secondTimestamp),
                failurePoint: .afterDocuments
            )
            Issue.record("Expected the generation commit to fail")
        } catch {
            #expect(error as? MacBrainDatabaseError == .injectedFailure)
        }

        #expect(try await fixture.database.searchChunks(matching: "OLD-VERIFIED").count == 1)
        #expect(try await fixture.database.searchChunks(matching: "NEW-UNCOMMITTED").isEmpty)
        #expect(try await fixture.database.connectorRecord(id: fixture.sourceID) == previouslyCommittedRecord)
        #expect(try await fixture.database.indexHealth(sourceID: fixture.sourceID)?.contentRevision == "r1")
        #expect(try await fixture.database.indexHealth(sourceID: fixture.sourceID)?.documentCount == 1)
    }

    @Test
    func reconciledGenerationUpdatesOnlyTheChangedAndRemovedDocuments() async throws {
        let fixture = try SourceCommitFixture()
        let firstTimestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let unchanged = fixture.document(externalID: "keep", marker: "KEEP-STABLE")
        let oldVersion = fixture.document(externalID: "change", marker: "OLD-VERSION")
        let removed = fixture.document(externalID: "remove", marker: "REMOVE-ME")
        _ = try await fixture.database.commitSourceGeneration(
            record: fixture.record(status: .ready, timestamp: firstTimestamp),
            documents: [unchanged, oldVersion, removed],
            health: fixture.health(revision: "r1", timestamp: firstTimestamp)
        )
        let stableChunkID = try #require(
            await fixture.database.searchChunks(matching: "KEEP-STABLE").first?.id
        )

        let secondTimestamp = firstTimestamp.addingTimeInterval(300)
        let newVersion = fixture.document(externalID: "change", marker: "NEW-VERSION")
        let added = fixture.document(externalID: "add", marker: "ADD-ME")
        let committed = try await fixture.database.commitReconciledSourceGeneration(
            record: fixture.record(status: .ready, timestamp: secondTimestamp),
            changedDocuments: [newVersion, added],
            presentExternalIDs: [unchanged.externalID, newVersion.externalID, added.externalID],
            health: fixture.health(revision: "placeholder", timestamp: secondTimestamp)
        )

        #expect(committed.documentCount == 3)
        #expect(committed.isSearchable)
        #expect(committed.contentRevision != "placeholder")
        #expect(try await fixture.database.searchChunks(matching: "KEEP-STABLE").first?.id == stableChunkID)
        #expect(try await fixture.database.searchChunks(matching: "OLD-VERSION").isEmpty)
        #expect(try await fixture.database.searchChunks(matching: "REMOVE-ME").isEmpty)
        #expect(try await fixture.database.searchChunks(matching: "NEW-VERSION").count == 1)
        #expect(try await fixture.database.searchChunks(matching: "ADD-ME").count == 1)
    }
}

private struct SourceCommitFixture {
    let sourceID = UUID()
    let database: MacBrainDatabase

    init() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "macbrain-source-commit-tests-" + UUID().uuidString,
                isDirectory: true
            )
            .appendingPathComponent("macbrain.sqlite")
        database = try MacBrainDatabase(url: databaseURL)
    }

    func record(status: ConnectorStatus, timestamp: Date) -> ConnectorRecord {
        ConnectorRecord(
            id: sourceID,
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(initialSyncCompleted: true),
            status: status,
            lastSuccessfulSync: timestamp,
            documentCount: 999
        )
    }

    func document(externalID: String, marker: String) -> StoredDocument {
        StoredDocument(
            sourceID: sourceID,
            externalID: externalID,
            title: marker,
            text: "Searchable text for \(marker)",
            sourceLabel: "Apple Notes"
        )
    }

    func health(revision: String, timestamp: Date) -> ConnectorIndexHealth {
        ConnectorIndexHealth(
            sourceID: sourceID,
            documentCount: 999,
            chunkCount: 999,
            contentRevision: revision,
            initialSyncCompleted: true,
            lastSuccessfulSync: timestamp,
            lastVerifiedAt: timestamp
        )
    }
}
