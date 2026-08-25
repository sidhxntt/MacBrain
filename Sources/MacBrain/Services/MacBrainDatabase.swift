import Foundation
import SQLite3

enum DatabaseWriteFailurePoint: Sendable { case afterDocument }

enum MacBrainDatabaseError: LocalizedError, Equatable, Sendable {
    case openFailed(String)
    case sqlite(String)
    case unsupportedSchema(Int)
    case injectedFailure

    var errorDescription: String? {
        switch self {
        case .openFailed(let message), .sqlite(let message): message
        case .unsupportedSchema(let version): "This MacBrain database uses unsupported schema version \(version)."
        case .injectedFailure: "Database write intentionally interrupted."
        }
    }
}

actor MacBrainDatabase: VectorStore {
    static let currentSchemaVersion = 4

    private let connection: SQLiteConnection
    private(set) var schemaVersion = 0

    init() throws {
        try self.init(url: MacBrainDatabase.defaultURL())
    }

    init(url: URL) throws {
        connection = try SQLiteConnection(url: url)
    }

    func migrate() throws {
        let current = try connection.integer("PRAGMA user_version")
        guard current <= Self.currentSchemaVersion else {
            throw MacBrainDatabaseError.unsupportedSchema(current)
        }

        for migration in migrations where migration.version > current {
            try connection.transaction {
                for statement in migration.statements {
                    try connection.execute(statement)
                }
                try connection.execute("PRAGMA user_version = \(migration.version)")
                try connection.execute(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                    [.integer(migration.version), .double(Date.now.timeIntervalSince1970)]
                )
            }
        }
        schemaVersion = try connection.integer("PRAGMA user_version")
    }

    func save(source: StoredSource) throws {
        try ensureMigrated()
        try connection.execute(
            """
            INSERT INTO sources(id, kind, display_name, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, display_name = excluded.display_name, updated_at = excluded.updated_at
            """,
            [.text(source.id.uuidString), .text(source.kind), .text(source.displayName), .double(source.createdAt.timeIntervalSince1970), .double(source.updatedAt.timeIntervalSince1970)]
        )
    }

    func save(connectorRecord: ConnectorRecord) throws {
        try save(
            source: StoredSource(
                id: connectorRecord.id,
                kind: connectorRecord.kind.rawValue,
                displayName: connectorRecord.displayName,
                updatedAt: connectorRecord.lastSuccessfulSync ?? .now
            )
        )
        try connection.execute(
            "INSERT INTO source_records(source_id, record_json) VALUES (?, ?) ON CONFLICT(source_id) DO UPDATE SET record_json = excluded.record_json",
            [.text(connectorRecord.id.uuidString), .blob(try JSONEncoder().encode(connectorRecord))]
        )
    }

    func connectorRecord(id: UUID) throws -> ConnectorRecord? {
        try ensureMigrated()
        guard let row = try connection.row("SELECT record_json FROM source_records WHERE source_id = ?", [.text(id.uuidString)]) else { return nil }
        return try JSONDecoder().decode(ConnectorRecord.self, from: row.data("record_json"))
    }

    func source(id: UUID) throws -> StoredSource? {
        try ensureMigrated()
        guard let row = try connection.row("SELECT id, kind, display_name, created_at, updated_at FROM sources WHERE id = ?", [.text(id.uuidString)]) else { return nil }
        return StoredSource(
            id: try row.uuid("id"),
            kind: try row.text("kind"),
            displayName: try row.text("display_name"),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at")
        )
    }

    func remove(sourceID: UUID) throws {
        try ensureMigrated()
        try connection.execute("DELETE FROM sources WHERE id = ?", [.text(sourceID.uuidString)])
    }

    func replace(
        document: StoredDocument,
        chunks: [StoredChunk],
        embeddings: [StoredEmbedding],
        failurePoint: DatabaseWriteFailurePoint? = nil
    ) throws {
        try ensureMigrated()
        try connection.transaction {
            let oldChunkIDs = try connection.rows("SELECT id FROM chunks WHERE document_id = ?", [.text(document.id.uuidString)])
                .compactMap { try? $0.text("id") }
            for chunkID in oldChunkIDs {
                try connection.execute("DELETE FROM chunks_fts WHERE chunk_id = ?", [.text(chunkID)])
            }
            try connection.execute("DELETE FROM chunks WHERE document_id = ?", [.text(document.id.uuidString)])

            try connection.execute(
                """
                INSERT INTO documents(id, source_id, external_id, title, text, source_label, content_hash, created_at, modified_at, is_deleted, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET source_id = excluded.source_id, external_id = excluded.external_id, title = excluded.title,
                    text = excluded.text, source_label = excluded.source_label, content_hash = excluded.content_hash,
                    created_at = excluded.created_at, modified_at = excluded.modified_at, is_deleted = excluded.is_deleted, metadata = excluded.metadata
                """,
                document.bindings
            )
            if failurePoint == .afterDocument { throw MacBrainDatabaseError.injectedFailure }

            for chunk in chunks {
                try connection.execute(
                    "INSERT INTO chunks(id, document_id, source_id, text, start_offset, end_offset, page_number, line_start, line_end, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)",
                    chunk.bindings
                )
                try connection.execute("INSERT INTO chunks_fts(chunk_id, normalized_text) VALUES (?, ?)", [.text(chunk.id.uuidString), .text(chunk.text.normalizedForSearch)])
            }
            for embedding in embeddings { try insert(embedding) }
        }
    }

    func replaceSourceDocuments(sourceID: UUID, documents: [StoredDocument]) throws {
        try ensureMigrated()
        try connection.transaction {
            let existingRows = try connection.rows(
                "SELECT id, external_id, content_hash, modified_at FROM documents WHERE source_id = ?",
                [.text(sourceID.uuidString)]
            )
            let existingByExternalID = Dictionary(
                uniqueKeysWithValues: try existingRows.map { row in
                    (try row.text("external_id"), ExistingSourceDocument(
                        id: try row.text("id"),
                        contentHash: try row.text("content_hash"),
                        modifiedAt: row.optionalDate("modified_at")
                    ))
                }
            )
            let incomingExternalIDs = Set(documents.map(\.externalID))
            let removed = existingByExternalID.filter { !incomingExternalIDs.contains($0.key) }.map(\.value)
            let changed = documents.filter { document in
                guard let existing = existingByExternalID[document.externalID] else { return true }
                return existing.contentHash != document.contentHash || existing.modifiedAt != document.modifiedAt
            }

            for existing in removed + changed.compactMap({ existingByExternalID[$0.externalID] }) {
                let chunkIDs = try connection.rows("SELECT id FROM chunks WHERE document_id = ?", [.text(existing.id)])
                    .compactMap { try? $0.text("id") }
                for chunkID in chunkIDs {
                    try connection.execute("DELETE FROM chunks_fts WHERE chunk_id = ?", [.text(chunkID)])
                }
                try connection.execute("DELETE FROM documents WHERE id = ?", [.text(existing.id)])
            }

            for document in changed {
                try connection.execute(
                    "INSERT INTO documents(id, source_id, external_id, title, text, source_label, content_hash, created_at, modified_at, is_deleted, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    document.bindings
                )
                let chunk = StoredChunk(
                    documentID: document.id,
                    sourceID: sourceID,
                    text: document.text,
                    startOffset: 0,
                    endOffset: document.text.utf16.count
                )
                try connection.execute(
                    "INSERT INTO chunks(id, document_id, source_id, text, start_offset, end_offset, page_number, line_start, line_end, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)",
                    chunk.bindings
                )
                try connection.execute("INSERT INTO chunks_fts(chunk_id, normalized_text) VALUES (?, ?)", [.text(chunk.id.uuidString), .text(chunk.text.normalizedForSearch)])
            }
        }
    }

    func document(id: UUID) throws -> StoredDocument? {
        try ensureMigrated()
        guard let row = try connection.row("SELECT id, source_id, external_id, title, text, source_label, content_hash, created_at, modified_at, is_deleted, metadata FROM documents WHERE id = ?", [.text(id.uuidString)]) else { return nil }
        return try StoredDocument(row: row)
    }

    func searchChunks(matching query: String, limit: Int = 10) throws -> [StoredChunk] {
        try ensureMigrated()
        let expression = query.searchExpression
        guard !expression.isEmpty else { return [] }
        let rows = try connection.rows(
            """
            SELECT c.id, c.document_id, c.source_id, c.text, c.start_offset, c.end_offset, c.page_number, c.line_start, c.line_end
            FROM chunks_fts
            JOIN chunks c ON c.id = chunks_fts.chunk_id
            WHERE chunks_fts MATCH ? AND c.is_deleted = 0
            ORDER BY rank
            LIMIT ?
            """,
            [.text(expression), .integer(limit)]
        )
        return try rows.map(StoredChunk.init(row:))
    }

    func searchDocuments(matching query: String, limit: Int = 5) throws -> [StoredDocument] {
        try ensureMigrated()
        let expression = query.searchExpression
        guard !expression.isEmpty else { return [] }
        let rows = try connection.rows(
            """
            SELECT d.id, d.source_id, d.external_id, d.title, d.text, d.source_label, d.content_hash,
                   d.created_at, d.modified_at, d.is_deleted, d.metadata
            FROM chunks_fts
            JOIN chunks c ON c.id = chunks_fts.chunk_id
            JOIN documents d ON d.id = c.document_id
            WHERE chunks_fts MATCH ? AND c.is_deleted = 0 AND d.is_deleted = 0
            ORDER BY rank
            LIMIT ?
            """,
            [.text(expression), .integer(limit)]
        )
        return try rows.map(StoredDocument.init(row:))
    }

    func upsert(_ embedding: StoredEmbedding) throws {
        try ensureMigrated()
        try insert(embedding)
    }

    func nearest(to vector: [Float], limit: Int) throws -> [UUID] {
        try nearestChunks(to: vector, limit: limit).map(\.id)
    }

    func nearestChunks(to vector: [Float], limit: Int) throws -> [StoredChunk] {
        try ensureMigrated()
        guard !vector.isEmpty else { return [] }
        let embeddings = try connection.rows("SELECT chunk_id, vector FROM embeddings")
        let scored = try embeddings.compactMap { row -> (UUID, Double)? in
            let chunkID = try row.uuid("chunk_id")
            let stored = try JSONDecoder().decode([Float].self, from: try row.data("vector"))
            return (chunkID, cosineSimilarity(vector, stored))
        }
        let bestIDs = scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        return try bestIDs.compactMap { id in
            guard let row = try connection.row("SELECT id, document_id, source_id, text, start_offset, end_offset, page_number, line_start, line_end FROM chunks WHERE id = ? AND is_deleted = 0", [.text(id.uuidString)]) else { return nil }
            return try StoredChunk(row: row)
        }
    }

    func remove(chunkID: UUID) throws {
        try ensureMigrated()
        try connection.transaction {
            try connection.execute("DELETE FROM embeddings WHERE chunk_id = ?", [.text(chunkID.uuidString)])
            try connection.execute("DELETE FROM chunks_fts WHERE chunk_id = ?", [.text(chunkID.uuidString)])
            try connection.execute("DELETE FROM chunks WHERE id = ?", [.text(chunkID.uuidString)])
        }
    }

    func save(conversation: StoredConversation, messages: [StoredMessage]) throws {
        try ensureMigrated()
        try connection.transaction {
            try connection.execute(
                """
                INSERT INTO conversations(id, title, greeting, created_at, updated_at, is_archived, is_pinned)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET title = excluded.title, greeting = excluded.greeting, updated_at = excluded.updated_at, is_archived = excluded.is_archived, is_pinned = excluded.is_pinned
                """,
                [.text(conversation.id.uuidString), .text(conversation.title), .text(conversation.greeting), .double(conversation.createdAt.timeIntervalSince1970), .double(conversation.updatedAt.timeIntervalSince1970), .integer(conversation.isArchived ? 1 : 0), .integer(conversation.isPinned ? 1 : 0)]
            )
            try connection.execute("DELETE FROM messages WHERE conversation_id = ?", [.text(conversation.id.uuidString)])
            for message in messages {
                try connection.execute("INSERT INTO messages(id, conversation_id, role, text, created_at) VALUES (?, ?, ?, ?, ?)", [.text(message.id.uuidString), .text(message.conversationID.uuidString), .text(message.role.rawValue), .text(message.text), .double(message.createdAt.timeIntervalSince1970)])
            }
        }
    }

    func conversation(id: UUID) throws -> StoredConversation? {
        try ensureMigrated()
        guard let row = try connection.row("SELECT id, title, greeting, created_at, updated_at, is_archived, is_pinned FROM conversations WHERE id = ?", [.text(id.uuidString)]) else { return nil }
        return try StoredConversation(row: row)
    }

    func conversations() throws -> [StoredConversation] {
        try ensureMigrated()
        return try connection.rows("SELECT id, title, greeting, created_at, updated_at, is_archived, is_pinned FROM conversations ORDER BY updated_at DESC").map(StoredConversation.init(row:))
    }

    func messages(conversationID: UUID) throws -> [StoredMessage] {
        try ensureMigrated()
        return try connection.rows("SELECT id, conversation_id, role, text, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at", [.text(conversationID.uuidString)]).map(StoredMessage.init(row:))
    }

    func replaceConversations(_ conversations: [(conversation: StoredConversation, messages: [StoredMessage])]) throws {
        try ensureMigrated()
        try connection.transaction {
            try connection.execute("DELETE FROM messages")
            try connection.execute("DELETE FROM conversations")
            for entry in conversations {
                try insert(entry.conversation)
                for message in entry.messages { try insert(message) }
            }
        }
    }

    func save(memory: StoredMemory) throws {
        try ensureMigrated()
        try connection.execute(
            """
            INSERT INTO memories(id, owner_id, text, created_at, updated_at) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET owner_id = excluded.owner_id, text = excluded.text, updated_at = excluded.updated_at
            """,
            [.text(memory.id.uuidString), .text(memory.ownerID), .text(memory.text), .double(memory.createdAt.timeIntervalSince1970), .double(memory.updatedAt.timeIntervalSince1970)]
        )
    }

    func memories(ownerID: String) throws -> [StoredMemory] {
        try ensureMigrated()
        return try connection.rows("SELECT id, owner_id, text, created_at, updated_at FROM memories WHERE owner_id = ? ORDER BY created_at", [.text(ownerID)]).map {
            StoredMemory(id: try $0.uuid("id"), ownerID: try $0.text("owner_id"), text: try $0.text("text"), createdAt: try $0.date("created_at"), updatedAt: try $0.date("updated_at"))
        }
    }

    func replaceGraph(for sourceID: UUID, entities: [StoredEntity], aliases: [String: UUID], mentions: [StoredMention], relationships: [StoredRelationship]) throws {
        try ensureMigrated()
        try connection.transaction {
            let entityIDs = try connection.rows("SELECT id FROM entities WHERE source_id = ?", [.text(sourceID.uuidString)]).compactMap { try? $0.text("id") }
            for entityID in entityIDs { try connection.execute("DELETE FROM entities WHERE id = ?", [.text(entityID)]) }
            for entity in entities {
                try connection.execute("INSERT INTO entities(id, source_id, type, name, created_at) VALUES (?, ?, ?, ?, ?)", [.text(entity.id.uuidString), .text(sourceID.uuidString), .text(entity.type), .text(entity.name), .double(entity.createdAt.timeIntervalSince1970)])
            }
            for (alias, entityID) in aliases { try connection.execute("INSERT INTO entity_aliases(entity_id, alias) VALUES (?, ?)", [.text(entityID.uuidString), .text(alias)]) }
            for mention in mentions { try connection.execute("INSERT INTO mentions(id, entity_id, chunk_id, start_offset, end_offset, confidence) VALUES (?, ?, ?, ?, ?, ?)", [.text(mention.id.uuidString), .text(mention.entityID.uuidString), .text(mention.chunkID.uuidString), .integer(mention.startOffset), .integer(mention.endOffset), .double(mention.confidence)]) }
            for relationship in relationships { try connection.execute("INSERT INTO relationships(id, from_entity_id, to_entity_id, type, provenance_chunk_id, confidence) VALUES (?, ?, ?, ?, ?, ?)", [.text(relationship.id.uuidString), .text(relationship.fromEntityID.uuidString), .text(relationship.toEntityID.uuidString), .text(relationship.type), relationship.provenanceChunkID.map { .text($0.uuidString) } ?? .null, .double(relationship.confidence)]) }
        }
    }

    func save(job: IndexingJob) throws {
        try ensureMigrated()
        try connection.execute("INSERT INTO indexing_jobs(id, source_id, state, detail, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET state = excluded.state, detail = excluded.detail, updated_at = excluded.updated_at", [.text(job.id.uuidString), .text(job.sourceID.uuidString), .text(job.state), job.detail.map(SQLiteValue.text) ?? .null, .double(job.createdAt.timeIntervalSince1970), .double(job.updatedAt.timeIntervalSince1970)])
    }

    private func insert(_ embedding: StoredEmbedding) throws {
        try connection.execute(
            "INSERT INTO embeddings(chunk_id, vector, index_identifier, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(chunk_id) DO UPDATE SET vector = excluded.vector, index_identifier = excluded.index_identifier, updated_at = excluded.updated_at",
            [.text(embedding.chunkID.uuidString), .blob(try JSONEncoder().encode(embedding.vector)), .text(embedding.indexIdentifier), .double(embedding.updatedAt.timeIntervalSince1970)]
        )
    }

    private func insert(_ conversation: StoredConversation) throws {
        try connection.execute(
            "INSERT INTO conversations(id, title, greeting, created_at, updated_at, is_archived, is_pinned) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [.text(conversation.id.uuidString), .text(conversation.title), .text(conversation.greeting), .double(conversation.createdAt.timeIntervalSince1970), .double(conversation.updatedAt.timeIntervalSince1970), .integer(conversation.isArchived ? 1 : 0), .integer(conversation.isPinned ? 1 : 0)]
        )
    }

    private func insert(_ message: StoredMessage) throws {
        try connection.execute("INSERT INTO messages(id, conversation_id, role, text, created_at) VALUES (?, ?, ?, ?, ?)", [.text(message.id.uuidString), .text(message.conversationID.uuidString), .text(message.role.rawValue), .text(message.text), .double(message.createdAt.timeIntervalSince1970)])
    }

    private func ensureMigrated() throws {
        if schemaVersion != Self.currentSchemaVersion { try migrate() }
    }

    private static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBrain", isDirectory: true)
            .appendingPathComponent("macbrain.sqlite")
    }
}

private struct ExistingSourceDocument {
    let id: String
    let contentHash: String
    let modifiedAt: Date?
}

private struct DatabaseMigration {
    let version: Int
    let statements: [String]
}

private let migrations: [DatabaseMigration] = [
    DatabaseMigration(version: 1, statements: [
        "PRAGMA foreign_keys = ON",
        "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS sources (id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, display_name TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS documents (id TEXT PRIMARY KEY NOT NULL, source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, external_id TEXT NOT NULL, title TEXT NOT NULL, text TEXT NOT NULL, source_label TEXT NOT NULL, content_hash TEXT NOT NULL, created_at REAL, modified_at REAL, is_deleted INTEGER NOT NULL DEFAULT 0, metadata BLOB NOT NULL, UNIQUE(source_id, external_id))",
        "CREATE TABLE IF NOT EXISTS chunks (id TEXT PRIMARY KEY NOT NULL, document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE, source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, text TEXT NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, page_number INTEGER, line_start INTEGER, line_end INTEGER, is_deleted INTEGER NOT NULL DEFAULT 0)",
        "CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(chunk_id UNINDEXED, normalized_text)",
        "CREATE TABLE IF NOT EXISTS embeddings (chunk_id TEXT PRIMARY KEY NOT NULL REFERENCES chunks(id) ON DELETE CASCADE, vector BLOB NOT NULL, index_identifier TEXT NOT NULL, updated_at REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, greeting TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL, is_archived INTEGER NOT NULL DEFAULT 0)",
        "CREATE TABLE IF NOT EXISTS messages (id TEXT PRIMARY KEY NOT NULL, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, role TEXT NOT NULL, text TEXT NOT NULL, created_at REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS memories (id TEXT PRIMARY KEY NOT NULL, owner_id TEXT NOT NULL, text TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS entities (id TEXT PRIMARY KEY NOT NULL, source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, type TEXT NOT NULL, name TEXT NOT NULL, created_at REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS entity_aliases (entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE, alias TEXT NOT NULL, PRIMARY KEY(entity_id, alias))",
        "CREATE TABLE IF NOT EXISTS mentions (id TEXT PRIMARY KEY NOT NULL, entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE, chunk_id TEXT NOT NULL REFERENCES chunks(id) ON DELETE CASCADE, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL, confidence REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS relationships (id TEXT PRIMARY KEY NOT NULL, from_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE, to_entity_id TEXT NOT NULL REFERENCES entities(id) ON DELETE CASCADE, type TEXT NOT NULL, provenance_chunk_id TEXT REFERENCES chunks(id) ON DELETE SET NULL, confidence REAL NOT NULL)",
        "CREATE TABLE IF NOT EXISTS indexing_jobs (id TEXT PRIMARY KEY NOT NULL, source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, state TEXT NOT NULL, detail TEXT, created_at REAL NOT NULL, updated_at REAL NOT NULL)"
    ]),
    DatabaseMigration(version: 2, statements: [
        "CREATE INDEX IF NOT EXISTS documents_source_hash_index ON documents(source_id, content_hash)",
        "CREATE INDEX IF NOT EXISTS documents_modified_index ON documents(modified_at)",
        "CREATE INDEX IF NOT EXISTS chunks_source_index ON chunks(source_id)",
        "CREATE INDEX IF NOT EXISTS messages_conversation_time_index ON messages(conversation_id, created_at)",
        "CREATE INDEX IF NOT EXISTS memories_owner_time_index ON memories(owner_id, updated_at)",
        "CREATE INDEX IF NOT EXISTS entities_name_index ON entities(name)",
        "CREATE INDEX IF NOT EXISTS relationships_endpoints_index ON relationships(from_entity_id, to_entity_id)",
        "CREATE INDEX IF NOT EXISTS jobs_source_state_index ON indexing_jobs(source_id, state)"
    ]),
    DatabaseMigration(version: 3, statements: [
        "ALTER TABLE conversations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0"
    ]),
    DatabaseMigration(version: 4, statements: [
        "CREATE TABLE IF NOT EXISTS source_records (source_id TEXT PRIMARY KEY NOT NULL REFERENCES sources(id) ON DELETE CASCADE, record_json BLOB NOT NULL)"
    ])
]

private enum SQLiteValue {
    case integer(Int)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

private final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let database else {
            throw MacBrainDatabaseError.openFailed("MacBrain could not open its local database.")
        }
        handle = database
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit { sqlite3_close(handle) }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        while true {
            let state = sqlite3_step(statement)
            if state == SQLITE_DONE { return }
            guard state == SQLITE_ROW else { throw error() }
        }
    }

    func row(_ sql: String, _ values: [SQLiteValue] = []) throws -> SQLiteRow? {
        try rows(sql, values).first
    }

    func rows(_ sql: String, _ values: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var result: [SQLiteRow] = []
        while true {
            let state = sqlite3_step(statement)
            if state == SQLITE_DONE { return result }
            guard state == SQLITE_ROW else { throw error() }
            var values: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: values[name] = .integer(Int(sqlite3_column_int64(statement, index)))
                case SQLITE_FLOAT: values[name] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT: values[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_blob(statement, index)
                    values[name] = .blob(Data(bytes: bytes!, count: Int(sqlite3_column_bytes(statement, index))))
                default: values[name] = .null
                }
            }
            result.append(SQLiteRow(values: values))
        }
    }

    func integer(_ sql: String) throws -> Int {
        guard let row = try row(sql), let value = row.values.values.first else { return 0 }
        switch value { case .integer(let number): return number; case .double(let number): return Int(number); default: return 0 }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .integer(let number): result = sqlite3_bind_int64(statement, index, sqlite3_int64(number))
            case .double(let number): result = sqlite3_bind_double(statement, index, number)
            case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
            case .blob(let data): result = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw error() }
        }
    }

    private func error() -> MacBrainDatabaseError {
        MacBrainDatabaseError.sqlite(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "MacBrain database error.")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct SQLiteRow {
    fileprivate let values: [String: SQLiteValue]

    func text(_ name: String) throws -> String {
        guard case .text(let value)? = values[name] else { throw MacBrainDatabaseError.sqlite("Missing text value \(name).") }
        return value
    }

    func integer(_ name: String) throws -> Int {
        switch values[name] { case .integer(let value): return value; case .double(let value): return Int(value); default: throw MacBrainDatabaseError.sqlite("Missing integer value \(name).") }
    }

    func double(_ name: String) throws -> Double {
        switch values[name] { case .double(let value): return value; case .integer(let value): return Double(value); default: throw MacBrainDatabaseError.sqlite("Missing number value \(name).") }
    }

    func data(_ name: String) throws -> Data {
        guard case .blob(let value)? = values[name] else { throw MacBrainDatabaseError.sqlite("Missing binary value \(name).") }
        return value
    }

    func uuid(_ name: String) throws -> UUID {
        guard let value = UUID(uuidString: try text(name)) else { throw MacBrainDatabaseError.sqlite("Invalid UUID value \(name).") }
        return value
    }

    func date(_ name: String) throws -> Date { Date(timeIntervalSince1970: try double(name)) }

    func optionalInteger(_ name: String) -> Int? { try? integer(name) }

    func optionalDate(_ name: String) -> Date? {
        guard let value = values[name] else { return nil }
        switch value {
        case .double(let seconds): return Date(timeIntervalSince1970: seconds)
        case .integer(let seconds): return Date(timeIntervalSince1970: Double(seconds))
        default: return nil
        }
    }
}

private extension StoredDocument {
    var bindings: [SQLiteValue] {
        [.text(id.uuidString), .text(sourceID.uuidString), .text(externalID), .text(title), .text(text), .text(sourceLabel), .text(contentHash), createdAt.map { .double($0.timeIntervalSince1970) } ?? .null, modifiedAt.map { .double($0.timeIntervalSince1970) } ?? .null, .integer(isDeleted ? 1 : 0), .blob((try? JSONEncoder().encode(metadata)) ?? Data())]
    }

    init(row: SQLiteRow) throws {
        self.init(id: try row.uuid("id"), sourceID: try row.uuid("source_id"), externalID: try row.text("external_id"), title: try row.text("title"), text: try row.text("text"), sourceLabel: try row.text("source_label"), createdAt: row.values["created_at"].flatMap { if case .double(let value) = $0 { Date(timeIntervalSince1970: value) } else { nil } }, modifiedAt: row.values["modified_at"].flatMap { if case .double(let value) = $0 { Date(timeIntervalSince1970: value) } else { nil } }, isDeleted: try row.integer("is_deleted") != 0, metadata: (try? JSONDecoder().decode([String: String].self, from: row.data("metadata"))) ?? [:])
    }
}

private extension StoredChunk {
    var bindings: [SQLiteValue] {
        [.text(id.uuidString), .text(documentID.uuidString), .text(sourceID.uuidString), .text(text), .integer(startOffset), .integer(endOffset), pageNumber.map(SQLiteValue.integer) ?? .null, lineStart.map(SQLiteValue.integer) ?? .null, lineEnd.map(SQLiteValue.integer) ?? .null]
    }

    init(row: SQLiteRow) throws {
        self.init(id: try row.uuid("id"), documentID: try row.uuid("document_id"), sourceID: try row.uuid("source_id"), text: try row.text("text"), startOffset: try row.integer("start_offset"), endOffset: try row.integer("end_offset"), pageNumber: row.optionalInteger("page_number"), lineStart: row.optionalInteger("line_start"), lineEnd: row.optionalInteger("line_end"))
    }
}

private extension StoredConversation {
    init(row: SQLiteRow) throws {
        self.init(id: try row.uuid("id"), title: try row.text("title"), greeting: try row.text("greeting"), createdAt: try row.date("created_at"), updatedAt: try row.date("updated_at"), isArchived: try row.integer("is_archived") != 0, isPinned: try row.integer("is_pinned") != 0)
    }
}

private extension StoredMessage {
    init(row: SQLiteRow) throws {
        guard let role = StoredMessageRole(rawValue: try row.text("role")) else {
            throw MacBrainDatabaseError.sqlite("Unknown stored message role.")
        }
        self.init(id: try row.uuid("id"), conversationID: try row.uuid("conversation_id"), role: role, text: try row.text("text"), createdAt: try row.date("created_at"))
    }
}

private extension String {
    var normalizedForSearch: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    var searchExpression: String {
        split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
            .joined(separator: " AND ")
    }
}

private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return -.infinity }
    let dot = zip(lhs, rhs).reduce(Float.zero) { $0 + $1.0 * $1.1 }
    let lhsLength = sqrt(lhs.reduce(Float.zero) { $0 + $1 * $1 })
    let rhsLength = sqrt(rhs.reduce(Float.zero) { $0 + $1 * $1 })
    guard lhsLength > 0, rhsLength > 0 else { return -.infinity }
    return Double(dot / (lhsLength * rhsLength))
}
