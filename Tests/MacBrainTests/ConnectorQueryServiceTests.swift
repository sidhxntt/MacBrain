import Foundation
import Testing
@testable import MacBrain

struct ConnectorQueryServiceTests {
    @Test
    func countAnswersFromVerifiedAuthorizedIndex() async throws {
        let fixture = try await ConnectorQueryFixture.make()

        let response = await fixture.service.response(
            for: .count,
            scope: [.appleNotes]
        )

        #expect(response.contains("3 notes"))
        #expect(response.contains("Apple Notes"))
    }

    @Test
    func multiSourceCountAggregatesOnlyRequestedVerifiedSources() async throws {
        let fixture = try await ConnectorQueryFixture.make()

        let response = await fixture.service.response(
            for: .count,
            scope: [.appleNotes, .appleMail]
        )

        #expect(response.contains("5 indexed items"))
        #expect(response.contains("Apple Mail"))
        #expect(response.contains("Apple Notes"))
    }

    @Test
    func countUsesTheLastVerifiedGenerationDuringAnInProgressRefresh() async throws {
        let fixture = try await ConnectorQueryFixture.make()

        // Simulate an interrupted refresh: documents have changed, but no new
        // verified generation has been published. A user-facing count must use
        // the committed index snapshot, not expose this partial state.
        try await fixture.database.replaceSourceDocuments(
            sourceID: fixture.notesID,
            documents: (0..<4).map { index in
                StoredDocument(
                    sourceID: fixture.notesID,
                    externalID: "refreshing-note-\(index)",
                    title: "Refreshing note \(index)",
                    text: "Refreshing note \(index)",
                    sourceLabel: "Notes: Personal"
                )
            }
        )

        let response = await fixture.service.response(for: .count, scope: [.appleNotes])

        #expect(response.contains("3 notes"))
        #expect(!response.contains("4 notes"))
    }

    @Test
    func unavailableStatesAreDistinguishedWithoutGuessing() async throws {
        let fixture = try await ConnectorQueryFixture.make()

        let disconnected = await fixture.service.response(for: .count, scope: [.contacts])
        let permission = await fixture.service.response(for: .count, scope: [.messages])
        let indexing = await fixture.service.response(for: .count, scope: [.photos])
        let empty = await fixture.service.response(for: .count, scope: [.books])

        #expect(disconnected.contains("isn’t connected"))
        #expect(permission.contains("permission"))
        #expect(permission.contains("not searchable"))
        #expect(indexing.contains("first searchable index"))
        #expect(empty.contains("0 books"))
        #expect(empty.contains("verified"))
    }

    @Test
    func newestResultIncludesTitleSourceAndStoredDate() async throws {
        let fixture = try await ConnectorQueryFixture.make()

        let response = await fixture.service.response(
            for: .newest(limit: 1),
            scope: [.appleNotes]
        )

        #expect(response.contains("Newest controlled note"))
        #expect(response.contains("Notes: Personal"))
        #expect(response.contains("Modified"))
    }

    @Test
    func calendarAndReminderOperationsRenderMetadataDates() async throws {
        let fixture = try await ConnectorQueryFixture.make()

        let event = await fixture.service.response(for: .nextEvent, scope: [.calendar])
        let reminder = await fixture.service.response(
            for: .firstDueReminder,
            scope: [.reminders]
        )

        #expect(event.contains("Next controlled event"))
        #expect(event.contains("Starts"))
        #expect(reminder.contains("First due controlled reminder"))
        #expect(reminder.contains("Due"))
    }
}

private struct ConnectorQueryFixture {
    let service: ConnectorQueryService
    let database: MacBrainDatabase
    let notesID: UUID

    static func make() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-query-service-tests-" + UUID().uuidString,
            isDirectory: true
        )
        let database = try MacBrainDatabase(
            url: directory.appendingPathComponent("macbrain.sqlite")
        )
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("local-sources.json"),
            database: database
        )
        try await repository.bootstrap()
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        let notesID = try await commit(
            repository: repository,
            kind: .appleNotes,
            documents: [
                ("Old note", now.addingTimeInterval(-300), [:]),
                ("Middle note", now.addingTimeInterval(-200), [:]),
                ("Newest controlled note", now.addingTimeInterval(-100), [:]),
            ],
            sourceLabel: "Notes: Personal"
        )
        _ = try await commit(
            repository: repository,
            kind: .appleMail,
            documents: [
                ("First mail", now.addingTimeInterval(-300), [:]),
                ("Second mail", now.addingTimeInterval(-200), [:]),
            ],
            sourceLabel: "Mail: Inbox"
        )
        _ = try await commit(
            repository: repository,
            kind: .books,
            documents: [],
            sourceLabel: "Apple Books"
        )
        _ = try await commit(
            repository: repository,
            kind: .calendar,
            documents: [
                (
                    "Past event",
                    now,
                    ["start": now.addingTimeInterval(-3_600).ISO8601Format()]
                ),
                (
                    "Next controlled event",
                    now,
                    ["start": now.addingTimeInterval(1_800).ISO8601Format()]
                ),
            ],
            sourceLabel: "Calendar: Work"
        )
        _ = try await commit(
            repository: repository,
            kind: .reminders,
            documents: [
                (
                    "Completed reminder",
                    now,
                    [
                        "completed": "true",
                        "due": now.addingTimeInterval(300).ISO8601Format(),
                    ]
                ),
                (
                    "First due controlled reminder",
                    now,
                    [
                        "completed": "false",
                        "due": now.addingTimeInterval(600).ISO8601Format(),
                    ]
                ),
            ],
            sourceLabel: "Reminders: Work"
        )

        let permissionRecord = ConnectorRecord(
            kind: .messages,
            displayName: "Messages",
            configuration: .init(),
            status: .needsAuthorization,
            lastError: "Full Disk Access required"
        )
        try await repository.save(permissionRecord)
        let indexingRecord = ConnectorRecord(
            kind: .photos,
            displayName: "Photos metadata",
            configuration: .init(),
            status: .syncing
        )
        try await repository.save(indexingRecord)

        return Self(
            service: ConnectorQueryService(repository: repository, now: { now }),
            database: database,
            notesID: notesID
        )
    }

    private static func commit(
        repository: LocalSourceRepository,
        kind: SourceConnectorKind,
        documents: [(title: String, modifiedAt: Date, metadata: [String: String])],
        sourceLabel: String
    ) async throws -> UUID {
        let record = ConnectorRecord(
            kind: kind,
            displayName: kind.displayName,
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        _ = try await repository.commitSourceGeneration(
            record: record,
            documents: documents.enumerated().map { index, item in
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "\(kind.rawValue)-\(index)",
                    title: item.title,
                    text: item.title,
                    sourceLabel: sourceLabel,
                    modifiedAt: item.modifiedAt,
                    metadata: item.metadata
                )
            }
        )
        return record.id
    }
}
