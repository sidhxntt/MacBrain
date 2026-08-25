import XCTest
@testable import MacBrain

final class MacBrainDatabaseTests: XCTestCase {
    func testFreshDatabaseMigratesAndPersistsCoreRecords() async throws {
        let url = try temporaryDatabaseURL()
        let database = try MacBrainDatabase(url: url)
        try await database.migrate()

        let source = StoredSource(id: UUID(), kind: "folder", displayName: "Work")
        let conversation = StoredConversation(id: UUID(), title: "Storage plan", greeting: "Hello")
        let memory = StoredMemory(id: UUID(), ownerID: "local-user", text: "Use local-first storage")

        try await database.save(source: source)
        try await database.save(conversation: conversation, messages: [
            StoredMessage(conversationID: conversation.id, role: .user, text: "Persist this")
        ])
        try await database.save(memory: memory)

        let reloaded = try MacBrainDatabase(url: url)
        try await reloaded.migrate()

        let persistedSource = try await reloaded.source(id: source.id)
        let persistedConversation = try await reloaded.conversation(id: conversation.id)
        let persistedMemories = try await reloaded.memories(ownerID: "local-user")
        let version = await reloaded.schemaVersion
        XCTAssertEqual(persistedSource?.id, source.id)
        XCTAssertEqual(persistedSource?.kind, source.kind)
        XCTAssertEqual(persistedSource?.displayName, source.displayName)
        XCTAssertEqual(persistedConversation?.title, "Storage plan")
        XCTAssertEqual(persistedMemories.map(\.id), [memory.id])
        XCTAssertEqual(persistedMemories.map(\.text), [memory.text])
        XCTAssertEqual(version, MacBrainDatabase.currentSchemaVersion)
    }

    func testDocumentWriteIsAtomicAndProvidesFTSAndVectorSearch() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        try await database.migrate()

        let sourceID = UUID()
        try await database.save(source: StoredSource(id: sourceID, kind: "notes", displayName: "Notes"))
        let document = StoredDocument(
            id: UUID(),
            sourceID: sourceID,
            externalID: "notes/local-first",
            title: "Local-first retrieval",
            text: "SQLite FTS keeps MacBrain local and searchable.",
            sourceLabel: "Notes"
        )
        let chunk = StoredChunk(
            id: UUID(),
            documentID: document.id,
            sourceID: sourceID,
            text: document.text,
            startOffset: 0,
            endOffset: document.text.count
        )

        try await database.replace(document: document, chunks: [chunk], embeddings: [
            StoredEmbedding(chunkID: chunk.id, vector: [1, 0, 0], indexIdentifier: "local")
        ])

        let ftsMatches = try await database.searchChunks(matching: "FTS local")
        let documentMatches = try await database.searchDocuments(matching: "FTS local")
        let vectorMatches = try await database.nearestChunks(to: [0.9, 0.1, 0], limit: 1)
        XCTAssertEqual(ftsMatches.map(\.id), [chunk.id])
        XCTAssertEqual(documentMatches.map(\.id), [document.id])
        XCTAssertEqual(vectorMatches.map(\.id), [chunk.id])

        let rejected = StoredDocument(
            id: UUID(),
            sourceID: sourceID,
            externalID: "notes/rejected",
            title: "Rejected",
            text: "This row must not survive a failed transaction.",
            sourceLabel: "Notes"
        )
        await XCTAssertThrowsErrorAsync {
            try await database.replace(document: rejected, chunks: [], embeddings: [], failurePoint: .afterDocument)
        }
        let rejectedDocument = try await database.document(id: rejected.id)
        XCTAssertNil(rejectedDocument)
    }

    func testSourceRepositoryMirrorsLiveConnectorDocumentsIntoSQLite() async throws {
        let databaseURL = try temporaryDatabaseURL()
        let database = try MacBrainDatabase(url: databaseURL)
        let repository = LocalSourceRepository(fileURL: try temporaryDatabaseURL(), database: database)
        let record = ConnectorRecord(kind: .folder, displayName: "Work", configuration: .init())
        let document = ConnectorDocument(
            connectorID: record.id,
            externalID: "work/decision.md",
            title: "Local storage decision",
            text: "Use SQLite FTS for the local evidence store.",
            sourceLabel: "Work"
        )

        try await repository.save(record)
        _ = try await repository.replaceDocuments(for: record.id, with: [document])

        let mirroredRecord = try await database.connectorRecord(id: record.id)
        let matches = try await database.searchChunks(matching: "SQLite evidence")
        XCTAssertEqual(mirroredRecord?.configuration.localPath, record.configuration.localPath)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.text, document.text)
    }

    func testFilenameAndRelativePathAreSearchableLocalEvidence() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let repository = LocalSourceRepository(fileURL: try temporaryDatabaseURL(), database: database)
        let record = ConnectorRecord(kind: .folder, displayName: "Test folder", configuration: .init())
        let document = ConnectorDocument(
            connectorID: record.id,
            externalID: "/tmp/test/nested/notes.md",
            title: "Release decisions",
            text: "Ship the local-first plan.",
            sourceLabel: "Test folder",
            metadata: [
                "path": "/tmp/test/nested/notes.md",
                "relativePath": "nested/notes.md"
            ]
        )

        try await repository.save(record)
        _ = try await repository.replaceDocuments(for: record.id, with: [document])

        let matches = await repository.search("notes.md")
        let response = try await LocalKnowledgeResponder(repository: repository)
            .respond(to: "What's there in my notes.md?")

        XCTAssertEqual(matches.map(\.externalID), [document.externalID])
        XCTAssertTrue(response.contains("Ship the local-first plan."))
        XCTAssertFalse(response.contains("not directly accessible"))
    }

    func testRepeatedUnchangedSourceSyncKeepsCachedIndexEntries() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let sourceStoreURL = try temporaryDatabaseURL()
        let repository = LocalSourceRepository(fileURL: sourceStoreURL, database: database)
        let record = ConnectorRecord(kind: .folder, displayName: "Work", configuration: .init())
        try await repository.save(record)

        for _ in 0..<50 {
            _ = try await repository.replaceDocuments(
                for: record.id,
                with: [ConnectorDocument(
                    connectorID: record.id,
                    externalID: "work/decision.md",
                    title: "Local cache decision",
                    text: "Reuse unchanged indexed evidence.",
                    sourceLabel: "Work"
                )]
            )
        }

        let matches = try await database.searchChunks(matching: "unchanged evidence")
        XCTAssertEqual(matches.count, 1)
        let stableChunkID = try XCTUnwrap(matches.first?.id)

        let reopenedRepository = LocalSourceRepository(fileURL: sourceStoreURL, database: database)
        _ = try await reopenedRepository.replaceDocuments(
            for: record.id,
            with: [ConnectorDocument(
                connectorID: record.id,
                externalID: "work/decision.md",
                title: "Local cache decision",
                text: "Reuse unchanged indexed evidence.",
                sourceLabel: "Work"
            )]
        )
        let cachedChunkID = try await database.searchChunks(matching: "unchanged evidence").first?.id
        XCTAssertEqual(cachedChunkID, stableChunkID)
    }

    func testSourceSyncIndexesOnlyNewChangedAndRemovedFiles() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let repository = LocalSourceRepository(fileURL: try temporaryDatabaseURL(), database: database)
        let record = ConnectorRecord(kind: .folder, displayName: "Work", configuration: .init())
        try await repository.save(record)

        _ = try await repository.replaceDocuments(for: record.id, with: [
            ConnectorDocument(connectorID: record.id, externalID: "a.md", title: "A", text: "alpha original", sourceLabel: "Work"),
            ConnectorDocument(connectorID: record.id, externalID: "b.md", title: "B", text: "bravo unchanged", sourceLabel: "Work")
        ])
        let initialUnchangedChunk = try await database.searchChunks(matching: "bravo").first
        let unchangedChunkID = try XCTUnwrap(initialUnchangedChunk?.id)

        _ = try await repository.replaceDocuments(for: record.id, with: [
            ConnectorDocument(connectorID: record.id, externalID: "a.md", title: "A", text: "alpha revised", sourceLabel: "Work"),
            ConnectorDocument(connectorID: record.id, externalID: "b.md", title: "B", text: "bravo unchanged", sourceLabel: "Work"),
            ConnectorDocument(connectorID: record.id, externalID: "c.md", title: "C", text: "charlie added", sourceLabel: "Work")
        ])

        let oldAlpha = try await database.searchChunks(matching: "original")
        let newAlpha = try await database.searchChunks(matching: "revised")
        let unchangedChunk = try await database.searchChunks(matching: "bravo").first
        let newFile = try await database.searchChunks(matching: "charlie").first
        XCTAssertTrue(oldAlpha.isEmpty)
        XCTAssertEqual(newAlpha.count, 1)
        XCTAssertEqual(unchangedChunk?.id, unchangedChunkID)
        XCTAssertNotNil(newFile)

        _ = try await repository.replaceDocuments(for: record.id, with: [
            ConnectorDocument(connectorID: record.id, externalID: "b.md", title: "B", text: "bravo unchanged", sourceLabel: "Work"),
            ConnectorDocument(connectorID: record.id, externalID: "c.md", title: "C", text: "charlie added", sourceLabel: "Work")
        ])
        let removedFile = try await database.searchChunks(matching: "revised")
        let finalUnchangedChunk = try await database.searchChunks(matching: "bravo").first
        XCTAssertTrue(removedFile.isEmpty)
        XCTAssertEqual(finalUnchangedChunk?.id, unchangedChunkID)
    }

    func testSourcePersistenceSplitsLongDocumentsIntoCitationChunks() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let repository = LocalSourceRepository(fileURL: try temporaryDatabaseURL(), database: database)
        let record = ConnectorRecord(kind: .folder, displayName: "Work", configuration: .init())
        let text = Array(repeating: "Local citations retain exact chunk offsets.", count: 80).joined(separator: "\n")
        try await repository.save(record)

        _ = try await repository.replaceDocuments(for: record.id, with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "work/long.md",
                title: "Long document",
                text: text,
                sourceLabel: "Work",
                metadata: ["format": "md"]
            )
        ])

        let chunks = try await database.searchChunks(matching: "citations offsets")
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.first?.startOffset, 0)
        XCTAssertNotNil(chunks.first?.lineStart)
        XCTAssertNotNil(chunks.last?.lineEnd)
    }

    func testChatSessionRepositoryRestoresMessagesArchiveAndPinState() async throws {
        let repository = try LocalChatSessionRepository(database: MacBrainDatabase(url: try temporaryDatabaseURL()))
        let open = ChatSession(
            title: "Local decisions",
            messages: [ChatMessage(role: .user, text: "Keep this offline")],
            greeting: "Welcome back"
        )
        let archived = ChatSession(title: "Old chat", messages: [], greeting: "Earlier")

        try await repository.replace(open: [open], archived: [archived], pinnedSessionIDs: [open.id])
        let restored = try await repository.load()

        XCTAssertEqual(restored.open.map(\.id), [open.id])
        XCTAssertEqual(restored.open.first?.messages.map(\.text), ["Keep this offline"])
        XCTAssertEqual(restored.archived.map(\.id), [archived.id])
        XCTAssertEqual(restored.pinnedSessionIDs, [open.id])
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBrainDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("macbrain.sqlite")
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {}
}
