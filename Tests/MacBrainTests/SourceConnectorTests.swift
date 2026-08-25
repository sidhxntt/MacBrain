@testable import MacBrain
import Contacts
import Foundation
import XCTest

final class SourceConnectorTests: XCTestCase {
    func testFolderIndexesSupportedFilesRecursivelyAndSkipsExcludedDirectories() async throws {
        let directory = try makeTemporaryDirectory()
        let nestedDirectory = directory.appendingPathComponent("Projects/Launch", isDirectory: true)
        let excludedDirectory = directory.appendingPathComponent("node_modules/package", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excludedDirectory, withIntermediateDirectories: true)
        try Data("# Launch\nShip Folder indexing.".utf8).write(to: nestedDirectory.appendingPathComponent("brief.md"))
        try Data("run: \n\techo local".utf8).write(to: directory.appendingPathComponent("Makefile"))
        try Data("Do not index me.".utf8).write(to: excludedDirectory.appendingPathComponent("package.txt"))
        let record = ConnectorRecord(
            kind: .folder,
            displayName: "Work",
            configuration: SourceConnectorConfiguration(localPath: directory.path)
        )

        let documents = try await FolderConnector().sync(record: record)

        XCTAssertEqual(documents.count, 2)
        let brief = try XCTUnwrap(documents.first { $0.metadata["relativePath"] == "Projects/Launch/brief.md" })
        XCTAssertEqual(brief.title, "Launch")
        XCTAssertTrue(documents.contains { $0.metadata["relativePath"] == "Makefile" })
    }

    func testFolderIndexesHiddenAndSecretFilesWhileSkippingDependencyAndBuildDirectories() async throws {
        let directory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".config", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("node_modules/package", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("dist", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("TOKEN=local-secret".utf8).write(to: directory.appendingPathComponent(".env"))
        try Data("TOKEN=local-secret".utf8).write(to: directory.appendingPathComponent(".env.local"))
        try Data("{\"apiKey\": \"local-secret\"}".utf8).write(
            to: directory.appendingPathComponent("credentials.json"))
        try Data("PRIVATE KEY".utf8).write(to: directory.appendingPathComponent("private.key"))
        try Data("CERTIFICATE".utf8).write(to: directory.appendingPathComponent("certificate.pem"))
        try Data("{\"theme\": \"dark\"}".utf8).write(
            to: directory.appendingPathComponent(".config/settings.json"))
        try Data("dependency".utf8).write(
            to: directory.appendingPathComponent("node_modules/package/index.txt"))
        try Data("built output".utf8).write(to: directory.appendingPathComponent("dist/app.txt"))
        let record = ConnectorRecord(
            kind: .folder,
            displayName: "Private work",
            configuration: SourceConnectorConfiguration(localPath: directory.path)
        )

        let documents = try await FolderConnector().sync(record: record)
        let paths = Set(documents.compactMap { $0.metadata["relativePath"] })

        XCTAssertTrue(paths.contains(".env"))
        XCTAssertTrue(paths.contains(".env.local"))
        XCTAssertTrue(paths.contains("credentials.json"))
        XCTAssertTrue(paths.contains("private.key"))
        XCTAssertTrue(paths.contains("certificate.pem"))
        XCTAssertTrue(paths.contains(".config/settings.json"))
        XCTAssertFalse(paths.contains("node_modules/package/index.txt"))
        XCTAssertFalse(paths.contains("dist/app.txt"))
    }

    func testFolderIndexesSingleLegacyTranscriptFileWithoutExposingTranscriptConnector() async throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("meeting.vtt")
        try Data("WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nDecision: ship local sources.\n".utf8).write(to: url)
        let record = ConnectorRecord(
            kind: .folder,
            displayName: "Meeting",
            configuration: SourceConnectorConfiguration(localPath: url.path)
        )

        let documents = try await FolderConnector().sync(record: record)

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].text, "Decision: ship local sources.")
    }

    func testRepositoryDeduplicatesSameExternalContent() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let connectorID = UUID()
        let one = ConnectorDocument(connectorID: connectorID, externalID: "same", title: "One", text: "Duplicate", sourceLabel: "Test")
        let duplicate = ConnectorDocument(connectorID: connectorID, externalID: "same", title: "One", text: "Duplicate", sourceLabel: "Test")

        let count = try await repository.replaceDocuments(for: connectorID, with: [one, duplicate])
        let storedCount = await repository.documentCount(for: connectorID)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(storedCount, 1)
    }

    func testRepositoryMergesConnectorBatchesWithoutDiscardingEarlierDocuments() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let connectorID = UUID()
        let first = ConnectorDocument(connectorID: connectorID, externalID: "one", title: "First", text: "One", sourceLabel: "Messages")
        let second = ConnectorDocument(connectorID: connectorID, externalID: "two", title: "Second", text: "Two", sourceLabel: "Messages")

        _ = try await repository.mergeDocuments(for: connectorID, with: [first])
        let count = try await repository.mergeDocuments(for: connectorID, with: [second])
        let storedCount = await repository.documentCount(for: connectorID)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(storedCount, 2)
    }

    func testAutomaticRefreshSkipsRecentlySyncedSource() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let connector = CountingConnector(kind: .folder)
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [connector])
        let record = ConnectorRecord(
            kind: .folder,
            displayName: "Work",
            configuration: .init(),
            lastSuccessfulSync: .now
        )
        try await repository.save(record)

        let store = await MainActor.run { SourceLibraryStore(repository: repository, coordinator: coordinator) }
        await store.refreshConnectedSourcesIfDue(referenceDate: Date.now)

        let syncCount = await connector.syncCount()
        XCTAssertEqual(syncCount, 0)
    }

    func testSourceConfigurationDecodesLegacyDataWithoutBatchFields() throws {
        let data = Data("{\"accountName\":\"Personal\"}".utf8)

        let configuration = try JSONDecoder().decode(SourceConnectorConfiguration.self, from: data)

        XCTAssertEqual(configuration.accountName, "Personal")
        XCTAssertNil(configuration.syncOffset)
        XCTAssertFalse(configuration.initialSyncCompleted)
    }

    func testLegacyTranscriptKindMigratesToFolder() throws {
        let kind = try JSONDecoder().decode(SourceConnectorKind.self, from: Data("\"transcript\"".utf8))

        XCTAssertEqual(kind, .folder)
    }

    func testLegacySafariKindMigratesToBrowserProfiles() throws {
        let kind = try JSONDecoder().decode(SourceConnectorKind.self, from: Data("\"safari\"".utf8))

        XCTAssertEqual(kind, .browserProfile)
    }

    func testLegacySafariRecordMigratesPausedUntilUserSelectsABrowserProfile() async throws {
        let storeURL = try temporaryStoreURL()
        let id = UUID().uuidString
        let data = Data("""
        {
          "schemaVersion": 1,
          "records": [{
            "id": "\(id)",
            "kind": "safari",
            "displayName": "Safari",
            "configuration": {},
            "status": "ready",
            "documentCount": 3
          }],
          "documents": []
        }
        """.utf8)
        try data.write(to: storeURL)

        let repository = LocalSourceRepository(fileURL: storeURL)
        let records = await repository.allRecords()
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.kind, .browserProfile)
        XCTAssertEqual(record.status, .paused)
        XCTAssertTrue(record.lastError?.contains("Choose a new Browser profile") == true)
    }

    func testBrowserProfileConfigurationPersistsSelectedBrowserAndProfile() throws {
        let configuration = SourceConnectorConfiguration(
            localPath: "/Profiles/Default",
            browserKind: .brave,
            browserProfileName: "Default"
        )

        let decoded = try JSONDecoder().decode(
            SourceConnectorConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        XCTAssertEqual(decoded.browserKind, .brave)
        XCTAssertEqual(decoded.browserProfileName, "Default")
        XCTAssertEqual(
            BrowserKind.allCases,
            [.safari, .chrome, .chromeCanary, .chromium, .genericChromium, .brave, .braveBeta, .braveNightly,
             .opera, .operaGX, .firefox, .firefoxDeveloperEdition, .firefoxNightly, .arc,
             .dia, .vivaldi, .edge, .edgeBeta, .edgeDev, .edgeCanary, .orion, .duckDuckGo, .torBrowser]
        )
        XCTAssertTrue(SourceConnectorKind.browserProfile.supportsMultipleConnections)
    }

    func testLegacyAutomaticallyCreatedSourcesAreClearedBeforeReload() async throws {
        let storeURL = try temporaryStoreURL()
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: SourceConnectorConfiguration()
        )
        let document = ConnectorDocument(
            connectorID: record.id,
            externalID: "legacy-note",
            title: "Old note",
            text: "This data was added before explicit connector consent.",
            sourceLabel: "Apple Notes"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(LegacySourceSnapshot(records: [record], documents: [document])).write(to: storeURL)

        let repository = LocalSourceRepository(fileURL: storeURL)
        let records = await repository.allRecords()
        let documentCount = await repository.documentCount(for: record.id)

        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(documentCount, 0)
    }

    @MainActor
    func testEveryConnectorShowsWhileLongRunningSyncContinues() async throws {
        for kind in SourceConnectorKind.userSelectableKinds {
            let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
            let coordinator = LocalSourceCoordinator(repository: repository, connectors: [DelayedConnector(kind: kind)])
            let store = SourceLibraryStore(repository: repository, coordinator: coordinator)

            store.addAndSync(kind: kind, displayName: kind.displayName, configuration: SourceConnectorConfiguration())
            try await Task.sleep(for: .milliseconds(40))

            XCTAssertEqual(store.records.first?.kind, kind)
            XCTAssertEqual(store.records.first?.status, .syncing)
        }
    }

    @MainActor
    func testSyncingOneConnectorDoesNotBlockAnotherConnector() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(
            repository: repository,
            connectors: [
                DelayedConnector(kind: .appleMail),
                DelayedConnector(kind: .calendar)
            ]
        )
        let store = SourceLibraryStore(repository: repository, coordinator: coordinator)

        store.addAndSync(kind: .appleMail, displayName: "Apple Mail", configuration: SourceConnectorConfiguration())
        store.addAndSync(kind: .calendar, displayName: "Apple Calendar", configuration: SourceConnectorConfiguration())
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(Set(store.records.map(\.kind)), [.appleMail, .calendar])
        XCTAssertTrue(store.isSyncing(kind: .appleMail))
        XCTAssertTrue(store.isSyncing(kind: .calendar))
    }

    @MainActor
    func testBrowserProfilesCreatesAndSyncsEachDetectedProfileOnlyOnce() async throws {
        let home = try makeTemporaryDirectory()
        let chromeRoot = home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: chromeRoot.appendingPathComponent("Default"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chromeRoot.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)

        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [BrowserProfileTestConnector()])
        let store = SourceLibraryStore(
            repository: repository,
            coordinator: coordinator,
            browserProfileCatalog: BrowserProfileCatalog(homeURL: home)
        )

        store.connectInstalledBrowserProfiles()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(store.records.count, 2)
        XCTAssertEqual(Set(store.records.map(\.displayName)), ["Chrome · Default", "Chrome · Profile 1"])
        XCTAssertTrue(store.records.allSatisfy { $0.status == .ready && $0.documentCount == 1 })

        store.connectInstalledBrowserProfiles()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(store.records.count, 2)
    }

    @MainActor
    func testBrowserProfilesConnectsARecognizedGenericChromiumProfile() async throws {
        let home = try makeTemporaryDirectory()
        let profile = home.appendingPathComponent("Library/Application Support/Example Browser/User Data/Default", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data().write(to: profile.appendingPathComponent("History"))

        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [BrowserProfileTestConnector()])
        let store = SourceLibraryStore(
            repository: repository,
            coordinator: coordinator,
            browserProfileCatalog: BrowserProfileCatalog(homeURL: home)
        )

        store.connectInstalledBrowserProfiles()
        try await Task.sleep(for: .milliseconds(120))

        let record = try XCTUnwrap(store.records.first)
        XCTAssertEqual(record.configuration.browserKind, .genericChromium)
        XCTAssertEqual(record.configuration.browserDisplayName, "Example Browser")
        XCTAssertEqual(record.displayName, "Example Browser · Default")
    }

    @MainActor
    func testAutomaticRefreshSyncsConnectedReadySources() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [SingleDocumentConnector()])
        let store = SourceLibraryStore(repository: repository, coordinator: coordinator)
        let record = try await coordinator.create(
            kind: .folder,
            displayName: "Standup",
            configuration: SourceConnectorConfiguration(localPath: "/tmp/standup.txt")
        )

        await store.refreshConnectedSourcesNow()

        let count = await repository.documentCount(for: record.id)
        let savedRecord = await repository.record(id: record.id)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(savedRecord?.status, .ready)
    }

    @MainActor
    func testAutomaticRefreshSkipsPausedSources() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [SingleDocumentConnector()])
        let store = SourceLibraryStore(repository: repository, coordinator: coordinator)
        let record = try await coordinator.create(
            kind: .folder,
            displayName: "Standup",
            configuration: SourceConnectorConfiguration(localPath: "/tmp/standup.txt")
        )
        try await coordinator.pause(id: record.id)

        await store.refreshConnectedSourcesNow()

        let count = await repository.documentCount(for: record.id)
        let savedRecord = await repository.record(id: record.id)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(savedRecord?.status, .paused)
    }

    @MainActor
    func testAutomaticRefreshRecordsAConciseActivityEntry() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [SingleDocumentConnector()])
        let store = SourceLibraryStore(repository: repository, coordinator: coordinator)
        _ = try await coordinator.create(
            kind: .folder,
            displayName: "Standup",
            configuration: SourceConnectorConfiguration(localPath: "/tmp/standup.txt")
        )

        await store.refreshConnectedSourcesNow()

        XCTAssertEqual(store.syncActivity.first?.sourceName, "Standup")
        XCTAssertEqual(store.syncActivity.first?.state, .completed)
    }

    @MainActor
    func testAutomaticRefreshRecordsAuthorizationNeedInSyncActivity() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [DeniedNotesConnector()])
        let store = SourceLibraryStore(repository: repository, coordinator: coordinator)
        _ = try await coordinator.create(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: SourceConnectorConfiguration(accountName: "iCloud")
        )

        await store.refreshConnectedSourcesNow()

        XCTAssertEqual(store.syncActivity.first?.sourceName, "Apple Notes")
        XCTAssertEqual(store.syncActivity.first?.state, .needsAttention)
        XCTAssertEqual(store.syncActivity.first?.detail, "Authorization required")
    }

    func testSyncActivityGroupsEventsByConnectorWithNewestGroupFirst() {
        let notesID = UUID()
        let browserProfileID = UUID()
        let activities = [
            SourceSyncActivity(
                sourceID: notesID,
                sourceName: "Apple Notes",
                state: .completed,
                detail: "Background refresh complete · 18 items",
                timestamp: Date(timeIntervalSince1970: 10)
            ),
            SourceSyncActivity(
                sourceID: browserProfileID,
                sourceName: "Chrome · Default",
                state: .needsAttention,
                detail: "Refresh needs attention",
                timestamp: Date(timeIntervalSince1970: 20)
            ),
            SourceSyncActivity(
                sourceID: notesID,
                sourceName: "Apple Notes",
                state: .syncing,
                detail: "Background refresh started",
                timestamp: Date(timeIntervalSince1970: 5)
            )
        ]

        let groups = activities.groupedBySource()

        XCTAssertEqual(groups.map(\.sourceName), ["Chrome · Default", "Apple Notes"])
        XCTAssertEqual(groups[0].activities.count, 1)
        XCTAssertEqual(groups[1].activities.map(\.detail), [
            "Background refresh complete · 18 items",
            "Background refresh started"
        ])
    }

    func testPermissionDenialChangesConnectorHealthWithoutSavingContent() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [DeniedNotesConnector()])
        let record = try await coordinator.create(
            kind: .appleNotes,
            displayName: "Notes: iCloud / Work",
            configuration: SourceConnectorConfiguration(accountName: "iCloud", containerName: "Work")
        )

        do {
            _ = try await coordinator.sync(id: record.id)
            XCTFail("Expected permission error")
        } catch let error as ConnectorError {
            XCTAssertEqual(error, .permissionDenied("Automation permission denied."))
        }

        let saved = await repository.record(id: record.id)
        let storedCount = await repository.documentCount(for: record.id)
        XCTAssertEqual(saved?.status, .needsAuthorization)
        XCTAssertEqual(storedCount, 0)
    }

    func testNotesPartialRowsCreateOnlyValidDocuments() async throws {
        let connector = AppleNotesConnector(scriptExecutor: FixedAppleScriptExecutor(
            output: "note-1\u{1E}Decision\u{1E}<b>Use local indexing</b>\u{1E}today\u{1D}incomplete"
        ))
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Notes",
            configuration: SourceConnectorConfiguration(accountName: "iCloud", containerName: "Work")
        )

        let documents = try await connector.sync(record: record)

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].title, "Decision")
        XCTAssertEqual(documents[0].text, "Use local indexing")
    }

    func testMailPreservesProvenanceMetadata() async throws {
        let connector = AppleMailConnector(scriptExecutor: FixedAppleScriptExecutor(
            output: "42\u{1E}Launch decision\u{1E}ana@example.com\u{1E}team@example.com\u{1E}Ship phase two\u{1E}2026-08-24\u{1E}<message@example.com>"
        ))
        let record = ConnectorRecord(kind: .appleMail, displayName: "Mail", configuration: SourceConnectorConfiguration(containerName: "Inbox"))

        let document = try await connector.sync(record: record).first

        XCTAssertEqual(document?.metadata["sender"], "ana@example.com")
        XCTAssertEqual(document?.metadata["recipients"], "team@example.com")
        XCTAssertEqual(document?.metadata["threadID"], "<message@example.com>")
        XCTAssertEqual(document?.metadata["mailbox"], "Inbox")
    }

    func testGitConnectorIncludesBranchesFilesAuthorAndReferences() async throws {
        let directory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Sources", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("node_modules/package", isDirectory: true), withIntermediateDirectories: true)
        try Data("struct App { let local = true }".utf8).write(to: directory.appendingPathComponent("Sources/App.swift"))
        try Data("TOKEN=local-secret".utf8).write(to: directory.appendingPathComponent(".env"))
        try Data("dependency".utf8).write(to: directory.appendingPathComponent("node_modules/package/index.txt"))
        let runner = FixedGitRunner(
            branches: "main\nrelease\n",
            commits: "\u{1E}abc123\u{1F}Ava\u{1F}ava@example.com\u{1F}2026-08-24T10:00:00Z\u{1F}Fix issue #42\nSources/App.swift\nREADME.md\n",
            trackedFiles: "Sources/App.swift\0.env\0node_modules/package/index.txt\0"
        )
        let connector = GitRepositoryConnector(runner: runner)
        let record = ConnectorRecord(
            kind: .gitRepository,
            displayName: "MacBrain",
            configuration: SourceConnectorConfiguration(localPath: directory.path, commitRange: "main")
        )

        let documents = try await connector.sync(record: record)

        XCTAssertEqual(documents.count, 3)
        let commit = try XCTUnwrap(documents.first { $0.metadata["author"] == "Ava" })
        let file = try XCTUnwrap(documents.first {
            $0.metadata["tracked"] == "true" && $0.metadata["relativePath"] == "Sources/App.swift"
        })
        XCTAssertEqual(commit.metadata["branches"], "main, release")
        XCTAssertEqual(commit.metadata["references"], "issue #42")
        XCTAssertTrue(commit.metadata["changedFiles"]?.contains("App.swift") == true)
        XCTAssertEqual(file.metadata["relativePath"], "Sources/App.swift")
        XCTAssertTrue(file.text.contains("local = true"))
        XCTAssertTrue(documents.contains { $0.metadata["relativePath"] == ".env" })
        XCTAssertFalse(documents.contains { $0.metadata["relativePath"] == "node_modules/package/index.txt" })
    }

    func testRemovalDeletesRecordAndSearchableContent() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [SingleDocumentConnector()])
        let record = try await coordinator.create(kind: .folder, displayName: "Standup", configuration: SourceConnectorConfiguration(localPath: "/tmp/standup.txt"))
        _ = try await coordinator.sync(id: record.id)
        let matchesBeforeRemoval = await repository.search("decision")
        XCTAssertEqual(matchesBeforeRemoval.count, 1)

        try await coordinator.remove(id: record.id)

        let removedRecord = await repository.record(id: record.id)
        let matchesAfterRemoval = await repository.search("decision")
        XCTAssertNil(removedRecord)
        XCTAssertTrue(matchesAfterRemoval.isEmpty)
    }

    func testPausedConnectorDoesNotSyncUntilResumed() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [SingleDocumentConnector()])
        let record = try await coordinator.create(kind: .folder, displayName: "Standup", configuration: SourceConnectorConfiguration(localPath: "/tmp/standup.txt"))

        try await coordinator.pause(id: record.id)
        let paused = try await coordinator.sync(id: record.id)
        let matchesWhilePaused = await repository.search("decision")
        XCTAssertEqual(paused.status, .paused)
        XCTAssertEqual(matchesWhilePaused.count, 0)

        try await coordinator.resume(id: record.id)
        _ = try await coordinator.sync(id: record.id)
        let matchesAfterResume = await repository.search("decision")
        XCTAssertEqual(matchesAfterResume.count, 1)
    }

    func testPausingDuringAnActiveSyncKeepsTheSourcePaused() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(
            repository: repository,
            connectors: [DelayedConnector(kind: .appleMail)]
        )
        let record = try await coordinator.create(
            kind: .appleMail,
            displayName: "Apple Mail",
            configuration: SourceConnectorConfiguration()
        )

        let syncTask = Task { try await coordinator.sync(id: record.id) }
        try await Task.sleep(for: .milliseconds(30))
        try await coordinator.pause(id: record.id)
        _ = try await syncTask.value

        let savedRecord = await repository.record(id: record.id)
        XCTAssertEqual(savedRecord?.status, .paused)
    }

    func testLocalKnowledgeResponderAnswersFromIndexedContent() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let connectorID = UUID()
        _ = try await repository.replaceDocuments(
            for: connectorID,
            with: [ConnectorDocument(
                connectorID: connectorID,
                externalID: "architecture",
                title: "Architecture decision",
                text: "Use only local retrieval for work context.",
                sourceLabel: "Transcript: architecture"
            )]
        )

        let response = try await LocalKnowledgeResponder(repository: repository).respond(to: "What did we decide about local retrieval?")

        XCTAssertTrue(response.contains("Architecture decision"))
        XCTAssertTrue(response.contains("Transcript: architecture"))
    }

    func testEveryConnectorKindIsAvailableForExplicitUserSelection() {
        XCTAssertEqual(Set(SourceConnectorKind.userSelectableKinds), Set(SourceConnectorKind.allCases))
    }

    func testMessagesConnectorPreservesConversationProvenance() async throws {
        let directory = try makeTemporaryDirectory()
        let databaseURL = directory.appendingPathComponent("chat.db")
        try Data().write(to: databaseURL)
        let connector = MessagesConnector(
            reader: FixedSQLiteReader(output: "1\u{1F}message-guid\u{1F}person@example.com\u{1F}Decision: use local-only sources\u{1F}2026-08-24 12:00:00\u{1F}chat-42\n"),
            databaseURL: databaseURL
        )
        let record = ConnectorRecord(kind: .messages, displayName: "Messages", configuration: SourceConnectorConfiguration())

        let documents = try await connector.sync(record: record)

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].metadata["chat"], "chat-42")
        XCTAssertEqual(documents[0].metadata["senderOrHandle"], "person@example.com")
    }

    func testMessagesInitialSyncUsesABoundedQuery() async throws {
        let directory = try makeTemporaryDirectory()
        let databaseURL = directory.appendingPathComponent("chat.db")
        try Data().write(to: databaseURL)
        let reader = CapturingSQLiteReader(output: "")
        let connector = MessagesConnector(reader: reader, databaseURL: databaseURL)
        let record = ConnectorRecord(kind: .messages, displayName: "Messages", configuration: SourceConnectorConfiguration())

        _ = try await connector.syncBatch(record: record)

        let query = await reader.lastQuery()
        XCTAssertTrue(query.contains("LIMIT 500 OFFSET 0"))
    }

    func testBatchedSyncPersistsProgressAndMergesAllBatches() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryStoreURL())
        let coordinator = LocalSourceCoordinator(repository: repository, connectors: [TwoBatchConnector()])
        let record = try await coordinator.create(
            kind: .messages,
            displayName: "Messages",
            configuration: SourceConnectorConfiguration()
        )

        let completed = try await coordinator.sync(id: record.id)
        let count = await repository.documentCount(for: record.id)

        XCTAssertEqual(completed.status, .ready)
        XCTAssertEqual(count, 2)
        XCTAssertTrue(completed.configuration.initialSyncCompleted)
        XCTAssertNil(completed.configuration.syncOffset)
        XCTAssertNil(completed.syncProgress)
    }

    func testBooksConnectorPreservesTitleAndAuthor() async throws {
        let connector = BooksConnector(
            reader: FixedSQLiteReader(output: "book-1\u{1F}Local First\u{1F}Ada Lovelace\u{1F}/Books/local-first.epub\n"),
            databaseURL: try makeTemporaryDirectory().appendingPathComponent("Books.sqlite")
        )
        let record = ConnectorRecord(kind: .books, displayName: "Apple Books", configuration: SourceConnectorConfiguration())

        let documents = try await connector.sync(record: record)

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].title, "Local First")
        XCTAssertEqual(documents[0].metadata["author"], "Ada Lovelace")
    }

    func testBooksConnectorTreatsMissingLocalLibraryAsAnEmptySource() async throws {
        let connector = BooksConnector(
            reader: FixedSQLiteReader(output: ""),
            libraryLocator: { nil }
        )
        let record = ConnectorRecord(kind: .books, displayName: "Apple Books", configuration: SourceConnectorConfiguration())

        let documents = try await connector.sync(record: record)

        XCTAssertTrue(documents.isEmpty)
    }

    func testNotesAndMailAutomationScriptsAreBuiltBeforeRequestingPermission() async throws {
        let executor = ScriptConstructionExecutor()
        let notes = AppleNotesConnector(scriptExecutor: executor)
        let mail = AppleMailConnector(scriptExecutor: executor)
        let notesRecord = ConnectorRecord(kind: .appleNotes, displayName: "Apple Notes", configuration: SourceConnectorConfiguration())
        let mailRecord = ConnectorRecord(kind: .appleMail, displayName: "Apple Mail", configuration: SourceConnectorConfiguration())

        do {
            _ = try await notes.sync(record: notesRecord)
        } catch {
            XCTFail("Notes script could not be built: \(error)")
        }
        do {
            _ = try await mail.sync(record: mailRecord)
        } catch {
            XCTFail("Mail script could not be built: \(error)")
        }
    }

    func testContactsFetchIncludesEveryNameFieldUsedByTheFormatter() {
        XCTAssertTrue(ContactsConnector.requiredKeyNames.contains(CNContactGivenNameKey))
        XCTAssertTrue(ContactsConnector.requiredKeyNames.contains(CNContactMiddleNameKey))
        XCTAssertTrue(ContactsConnector.requiredKeyNames.contains(CNContactFamilyNameKey))
        XCTAssertTrue(ContactsConnector.requiredKeyNames.contains(CNContactNicknameKey))
    }

    func testContactsBuildsDisplayNameWithoutContactFormatter() {
        XCTAssertEqual(
            ContactsConnector.displayName(
                givenName: "Ada", middleName: "Lovelace", familyName: "Byron", nickname: "Countess"
            ),
            "Ada Lovelace Byron"
        )
        XCTAssertEqual(
            ContactsConnector.displayName(givenName: "", middleName: "", familyName: "", nickname: "Countess"),
            "Countess"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func temporaryStoreURL() throws -> URL {
        try makeTemporaryDirectory().appendingPathComponent("sources.json")
    }
}

private struct FixedAppleScriptExecutor: AppleScriptExecuting {
    let output: String
    func execute(_ source: String) async throws -> String { output }
}

private struct LegacySourceSnapshot: Codable {
    let records: [ConnectorRecord]
    let documents: [ConnectorDocument]
}

private struct DelayedConnector: SourceConnector {
    let kind: SourceConnectorKind

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await Task.sleep(for: .milliseconds(300))
        return []
    }
}

private actor CountingConnector: SourceConnector {
    let kind: SourceConnectorKind
    private var count = 0

    init(kind: SourceConnectorKind) {
        self.kind = kind
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        count += 1
        return []
    }

    func syncCount() -> Int { count }
}

private struct DeniedNotesConnector: SourceConnector {
    let kind: SourceConnectorKind = .appleNotes
    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        throw ConnectorError.permissionDenied("Automation permission denied.")
    }
}

private struct SingleDocumentConnector: SourceConnector {
    let kind: SourceConnectorKind = .folder
    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        [ConnectorDocument(connectorID: record.id, externalID: "decision", title: "Decision", text: "Use local indexing", sourceLabel: "Folder")]
    }
}

private struct BrowserProfileTestConnector: SourceConnector {
    let kind: SourceConnectorKind = .browserProfile

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        [ConnectorDocument(
            connectorID: record.id,
            externalID: record.configuration.localPath ?? record.id.uuidString,
            title: record.displayName,
            text: "Browser profile",
            sourceLabel: "Browser"
        )]
    }
}

private struct FixedGitRunner: GitRunning {
    let branches: String
    let commits: String
    let trackedFiles: String

    func run(arguments: [String], at repositoryURL: URL) async throws -> String {
        if arguments.first == "branch" { return branches }
        if arguments.first == "ls-files" { return trackedFiles }
        return commits
    }
}

private struct EmptyConnector: SourceConnector {
    let kind: SourceConnectorKind
    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] { [] }
}

private struct FixedSQLiteReader: LocalSQLiteReading {
    let output: String
    func read(databaseURL: URL, query: String) async throws -> String { output }
}

private actor CapturingSQLiteReader: LocalSQLiteReading {
    let output: String
    private var query = ""

    init(output: String) {
        self.output = output
    }

    func read(databaseURL: URL, query: String) async throws -> String {
        self.query = query
        return output
    }

    func lastQuery() -> String { query }
}

private struct TwoBatchConnector: BatchedSourceConnector {
    let kind: SourceConnectorKind = .messages

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await syncBatch(record: record).documents
    }

    func syncBatch(record: ConnectorRecord) async throws -> ConnectorSyncBatch {
        let offset = record.configuration.syncOffset ?? 0
        let document = ConnectorDocument(
            connectorID: record.id,
            externalID: "message-\(offset)",
            title: "Message \(offset)",
            text: "Local message",
            sourceLabel: "Messages"
        )
        return ConnectorSyncBatch(
            documents: [document],
            nextOffset: offset == 0 ? 1 : nil,
            initialSyncCompleted: offset != 0,
            progressDescription: "Indexed batch \(offset + 1)"
        )
    }
}

private struct ScriptConstructionExecutor: AppleScriptExecuting {
    func execute(_ source: String) async throws -> String {
        guard source.contains("tell application"), source.contains("on scrub") else {
            throw ConnectorError.failed("AppleScript source was not built.")
        }
        return ""
    }
}
