import Foundation
import Testing
@testable import MacBrain

struct ConnectorStructuredQueryTests {
    @Test
    func countUsesOnlyCallerSuppliedEligibleSourceIDs() async throws {
        let fixture = try await StructuredQueryFixture.make()

        #expect(try await fixture.database.documentCount(sourceIDs: [fixture.notesID]) == 3)
        #expect(try await fixture.database.documentCount(sourceIDs: []) == 0)
        #expect(
            try await fixture.database.documentCount(
                sourceIDs: [fixture.notesID, fixture.permissionNeededNotesID]
            ) == 4
        )
    }

    @Test
    func newestAndOldestUseStoredDocumentDatesWithinScope() async throws {
        let fixture = try await StructuredQueryFixture.make()

        let newest = try await fixture.database.documents(
            sourceIDs: [fixture.notesID],
            ascending: false,
            limit: 1
        )
        let oldest = try await fixture.database.documents(
            sourceIDs: [fixture.notesID],
            ascending: true,
            limit: 1
        )

        #expect(newest.map(\.title) == ["Newest note"])
        #expect(oldest.map(\.title) == ["Oldest note"])
    }

    @Test
    func nextEventUsesStartMetadataRatherThanModificationDate() async throws {
        let fixture = try await StructuredQueryFixture.make()

        let result = try await fixture.database.documents(
            sourceIDs: [fixture.calendarID],
            metadataDateKey: "start",
            after: fixture.now,
            metadataEquals: [:],
            ascending: true,
            limit: 1
        )

        #expect(result.first?.title == "Next controlled event")
    }

    @Test
    func firstDueReminderExcludesCompletedAndMissingDueDates() async throws {
        let fixture = try await StructuredQueryFixture.make()

        let result = try await fixture.database.documents(
            sourceIDs: [fixture.remindersID],
            metadataDateKey: "due",
            after: nil,
            metadataEquals: ["completed": "false"],
            ascending: true,
            limit: 1
        )

        #expect(result.first?.title == "First incomplete reminder")
    }
}

private struct StructuredQueryFixture {
    let database: MacBrainDatabase
    let now: Date
    let notesID: UUID
    let permissionNeededNotesID: UUID
    let calendarID: UUID
    let remindersID: UUID

    static func make() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-structured-query-tests-" + UUID().uuidString,
            isDirectory: true
        )
        let database = try MacBrainDatabase(
            url: directory.appendingPathComponent("macbrain.sqlite")
        )
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let notesID = UUID()
        let permissionNeededNotesID = UUID()
        let calendarID = UUID()
        let remindersID = UUID()

        try await commit(
            database: database,
            record: readyRecord(id: notesID, kind: .appleNotes, now: now),
            documents: [
                document(sourceID: notesID, id: "old", title: "Oldest note", modifiedAt: now.addingTimeInterval(-300)),
                document(sourceID: notesID, id: "middle", title: "Middle note", modifiedAt: now.addingTimeInterval(-200)),
                document(sourceID: notesID, id: "new", title: "Newest note", modifiedAt: now.addingTimeInterval(-100)),
            ],
            now: now
        )
        try await commit(
            database: database,
            record: readyRecord(id: permissionNeededNotesID, kind: .appleNotes, now: now),
            documents: [document(sourceID: permissionNeededNotesID, id: "private", title: "Permission-needed note", modifiedAt: now)],
            now: now
        )
        var permissionRecord = readyRecord(
            id: permissionNeededNotesID,
            kind: .appleNotes,
            now: now
        )
        permissionRecord.status = .needsAuthorization
        try await database.save(connectorRecord: permissionRecord)

        try await commit(
            database: database,
            record: readyRecord(id: calendarID, kind: .calendar, now: now),
            documents: [
                document(
                    sourceID: calendarID,
                    id: "past",
                    title: "Past event",
                    modifiedAt: now.addingTimeInterval(1_000),
                    metadata: ["start": now.addingTimeInterval(-3_600).ISO8601Format()]
                ),
                document(
                    sourceID: calendarID,
                    id: "next",
                    title: "Next controlled event",
                    modifiedAt: now.addingTimeInterval(-1_000),
                    metadata: ["start": now.addingTimeInterval(1_800).ISO8601Format()]
                ),
                document(
                    sourceID: calendarID,
                    id: "later",
                    title: "Later event",
                    modifiedAt: now,
                    metadata: ["start": now.addingTimeInterval(7_200).ISO8601Format()]
                ),
            ],
            now: now
        )

        try await commit(
            database: database,
            record: readyRecord(id: remindersID, kind: .reminders, now: now),
            documents: [
                document(
                    sourceID: remindersID,
                    id: "completed",
                    title: "Completed reminder",
                    modifiedAt: now,
                    metadata: [
                        "completed": "true",
                        "due": now.addingTimeInterval(600).ISO8601Format(),
                    ]
                ),
                document(
                    sourceID: remindersID,
                    id: "first",
                    title: "First incomplete reminder",
                    modifiedAt: now,
                    metadata: [
                        "completed": "false",
                        "due": now.addingTimeInterval(1_200).ISO8601Format(),
                    ]
                ),
                document(
                    sourceID: remindersID,
                    id: "later",
                    title: "Later incomplete reminder",
                    modifiedAt: now,
                    metadata: [
                        "completed": "false",
                        "due": now.addingTimeInterval(2_400).ISO8601Format(),
                    ]
                ),
                document(
                    sourceID: remindersID,
                    id: "none",
                    title: "No due date",
                    modifiedAt: now,
                    metadata: ["completed": "false", "due": ""]
                ),
            ],
            now: now
        )

        return Self(
            database: database,
            now: now,
            notesID: notesID,
            permissionNeededNotesID: permissionNeededNotesID,
            calendarID: calendarID,
            remindersID: remindersID
        )
    }

    private static func readyRecord(
        id: UUID,
        kind: SourceConnectorKind,
        now: Date
    ) -> ConnectorRecord {
        ConnectorRecord(
            id: id,
            kind: kind,
            displayName: kind.displayName,
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: now
        )
    }

    private static func document(
        sourceID: UUID,
        id: String,
        title: String,
        modifiedAt: Date,
        metadata: [String: String] = [:]
    ) -> StoredDocument {
        StoredDocument(
            sourceID: sourceID,
            externalID: id,
            title: title,
            text: title,
            sourceLabel: title,
            modifiedAt: modifiedAt,
            metadata: metadata
        )
    }

    private static func commit(
        database: MacBrainDatabase,
        record: ConnectorRecord,
        documents: [StoredDocument],
        now: Date
    ) async throws {
        _ = try await database.commitSourceGeneration(
            record: record,
            documents: documents,
            health: ConnectorIndexHealth(
                sourceID: record.id,
                contentRevision: UUID().uuidString,
                initialSyncCompleted: true,
                lastSuccessfulSync: now,
                lastVerifiedAt: now
            )
        )
    }
}
