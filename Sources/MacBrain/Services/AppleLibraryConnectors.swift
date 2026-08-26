import Foundation
import SQLite3

struct MessagesConnector: BatchedSourceConnector {
    let kind: SourceConnectorKind = .messages
    let reader: any LocalSQLiteReading
    let databaseURL: URL
    private let batchSize = 500

    init(
        reader: any LocalSQLiteReading = LocalSQLiteReader(),
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Messages/chat.db")
    ) {
        self.reader = reader
        self.databaseURL = databaseURL
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await syncBatch(record: record).documents
    }

    func syncBatch(record: ConnectorRecord) async throws -> ConnectorSyncBatch {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw ConnectorError.sourceUnavailable("Messages history is unavailable on this Mac.")
        }
        guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
            throw ConnectorError.permissionDenied(
                "MacBrain needs Full Disk Access to read Messages. Enable it in System Settings, then retry this source."
            )
        }
        let cursor = record.configuration.syncOffset
        let cutoff = record.configuration.initialSyncCompleted
            ? record.lastSuccessfulSync.map { Int($0.timeIntervalSinceReferenceDate) }
            : nil
        let cutoffClause = cutoff.map {
            "AND (CASE WHEN m.date > 1000000000000 THEN m.date / 1000000000 ELSE m.date END) > \($0)"
        } ?? ""
        let cursorClause = cursor.map { "AND m.ROWID < \($0)" } ?? ""
        let query = """
        SELECT m.ROWID, COALESCE(m.guid, ''), COALESCE(h.id, ''), COALESCE(m.text, ''),
               datetime((CASE WHEN m.date > 1000000000000 THEN m.date / 1000000000 ELSE m.date END) + 978307200, 'unixepoch'),
               COALESCE(c.chat_identifier, '')
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
        LEFT JOIN chat c ON cmj.chat_id = c.ROWID
        WHERE m.text IS NOT NULL AND trim(m.text) != ''
        \(cutoffClause)
        \(cursorClause)
        ORDER BY m.ROWID DESC
        LIMIT \(batchSize);
        """
        let output = try await reader.read(databaseURL: databaseURL, query: query)
        let rows = output.split(whereSeparator: \.isNewline)
        let parsedRows: [(rowID: Int, document: ConnectorDocument)] = rows.compactMap { row in
            let parts = row.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6, let rowID = Int(parts[0]) else { return nil }
            return (rowID, ConnectorDocument(
                connectorID: record.id,
                externalID: parts[1].isEmpty ? parts[0] : parts[1],
                title: parts[2].isEmpty ? "Message" : "Message with \(parts[2])",
                text: parts[3],
                sourceLabel: parts[5].isEmpty ? "Messages" : "Messages: \(parts[5])",
                metadata: ["senderOrHandle": parts[2], "date": parts[4], "chat": parts[5]]
            ))
        }
        let documents = parsedRows.map(\.document)
        let hasMore = parsedRows.count == batchSize
        let nextOffset = hasMore ? parsedRows.last?.rowID : nil
        let phase = record.configuration.initialSyncCompleted ? "new messages" : "message history"
        return ConnectorSyncBatch(
            documents: documents,
            nextOffset: nextOffset,
            initialSyncCompleted: record.configuration.initialSyncCompleted || !hasMore,
            progressDescription: "Indexed \(documents.count) \(phase) in this batch"
        )
    }
}

struct BooksConnector: SourceConnector {
    let kind: SourceConnectorKind = .books
    let reader: any LocalSQLiteReading
    let databaseURL: URL?
    let libraryLocator: @Sendable () -> URL?

    init(
        reader: any LocalSQLiteReading = LocalSQLiteReader(),
        databaseURL: URL? = nil,
        libraryLocator: @escaping @Sendable () -> URL? = { BooksLibraryLocator.firstExistingDatabase() }
    ) {
        self.reader = reader
        self.databaseURL = databaseURL
        self.libraryLocator = libraryLocator
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        guard let databaseURL = databaseURL ?? libraryLocator() else {
            // Full Disk Access can be correctly granted while Books has not
            // created any local database yet. That is an empty source, not a failure.
            return []
        }
        let query = "SELECT ZASSETID, COALESCE(ZTITLE, ''), COALESCE(ZAUTHOR, ''), COALESCE(ZPATH, '') FROM ZBKLIBRARYASSET WHERE ZTITLE IS NOT NULL;"
        let output = try await reader.read(databaseURL: databaseURL, query: query)
        return output.split(whereSeparator: \.isNewline).compactMap { row in
            let parts = row.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4 else { return nil }
            return ConnectorDocument(
                connectorID: record.id,
                externalID: parts[0].isEmpty ? parts[1] : parts[0],
                title: parts[1].isEmpty ? "Untitled book" : parts[1],
                text: "Author: \(parts[2])\nLibrary path: \(parts[3])",
                sourceLabel: "Apple Books",
                metadata: ["author": parts[2], "path": parts[3]]
            )
        }
    }
}

protocol LocalSQLiteReading: Sendable {
    func read(databaseURL: URL, query: String) async throws -> String
}

/// Read-only feasibility check for replacing Apple Mail AppleScript access with
/// the local Mail store. It intentionally queries SQLite schema metadata only.
struct AppleMailLocalStoreProbe: Sendable {
    let reader: any LocalSQLiteReading
    let databaseLocator: @Sendable () -> URL?

    init(
        reader: any LocalSQLiteReading = LocalSQLiteReader(),
        databaseLocator: @escaping @Sendable () -> URL? = { AppleMailStoreLocator.firstExistingDatabase() }
    ) {
        self.reader = reader
        self.databaseLocator = databaseLocator
    }

    func run() async throws -> AppleMailLocalStoreProbeResult {
        guard let databaseURL = databaseLocator() else {
            throw ConnectorError.sourceUnavailable("MacBrain could not find Apple Mail’s local index on this Mac.")
        }
        let output = try await reader.read(
            databaseURL: databaseURL,
            query: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"
        )
        let tableNames = output.split(whereSeparator: \.isNewline).map(String.init)
        guard !tableNames.isEmpty else {
            throw ConnectorError.sourceUnavailable("Apple Mail’s local index is present but has no readable schema.")
        }
        return AppleMailLocalStoreProbeResult(databaseURL: databaseURL, tableNames: tableNames)
    }
}

struct AppleMailLocalStoreProbeResult: Sendable {
    let databaseURL: URL
    let tableNames: [String]
}

/// Reads Apple Mail's local Envelope Index directly. This avoids serial Apple
/// events and lets the coordinator complete the historical sync in one run.
struct AppleMailLocalStoreConnector: BatchedSourceConnector {
    let kind: SourceConnectorKind = .appleMail
    let reader: any LocalSQLiteReading
    let databaseLocator: @Sendable () -> URL?
    private let batchSize = 200

    init(
        reader: any LocalSQLiteReading = LocalSQLiteReader(),
        databaseLocator: @escaping @Sendable () -> URL? = { AppleMailStoreLocator.firstExistingDatabase() }
    ) {
        self.reader = reader
        self.databaseLocator = databaseLocator
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await syncBatch(record: record).documents
    }

    func syncBatch(record: ConnectorRecord) async throws -> ConnectorSyncBatch {
        guard let databaseURL = databaseLocator() else {
            throw ConnectorError.sourceUnavailable("Apple Mail’s local index is unavailable on this Mac.")
        }
        // The first local pass deliberately ignores the old AppleScript offset.
        // Those offsets counted mailbox enumeration, not SQLite row IDs.
        let cursor = record.documentCount > 50 ? record.configuration.syncOffset : nil
        let cursorClause = cursor.map { "AND m.ROWID < \($0)" } ?? ""
        let output = try await reader.read(databaseURL: databaseURL, query: """
            SELECT m.ROWID, m.message_id, COALESCE(g.message_id_header, ''),
                   COALESCE(s.subject, ''), COALESCE(a.address, ''), COALESCE(a.comment, ''),
                   COALESCE(su.summary, ''), COALESCE(mb.url, ''), COALESCE(m.date_received, 0)
            FROM messages m
            LEFT JOIN subjects s ON s.ROWID = m.subject
            LEFT JOIN sender_addresses sa ON sa.sender = m.sender
            LEFT JOIN addresses a ON a.ROWID = sa.address
            LEFT JOIN summaries su ON su.ROWID = m.summary
            LEFT JOIN mailboxes mb ON mb.ROWID = m.mailbox
            LEFT JOIN message_global_data g ON g.message_id = m.message_id
            WHERE m.deleted = 0
            \(cursorClause)
            ORDER BY m.ROWID DESC
            LIMIT \(batchSize);
            """)
        var rows: [(rowID: Int, document: ConnectorDocument)] = []
        for rawRow in output.components(separatedBy: .newlines) where !rawRow.isEmpty {
            let values = rawRow.components(separatedBy: "\u{1F}")
            guard values.count == 9, let rowID = Int(values[0]) else { continue }
            let subject = nonEmpty(values[3]) ?? "Untitled email"
            let sender = nonEmpty(values[4]) ?? nonEmpty(values[5]) ?? "Unknown sender"
            let summary = nonEmpty(values[6]) ?? "No local message preview is available."
            let received = TimeInterval(values[8]) ?? 0
            rows.append((rowID: rowID, document: ConnectorDocument(
                connectorID: record.id,
                externalID: nonEmpty(values[2]) ?? "mail-row-\(rowID)",
                title: subject,
                text: "From: \(sender)\nMailbox: \(values[7])\n\n\(summary)",
                sourceLabel: "Apple Mail",
                createdAt: received > 0 ? Date(timeIntervalSince1970: received) : nil,
                modifiedAt: received > 0 ? Date(timeIntervalSince1970: received) : nil,
                metadata: ["sender": sender, "mailbox": values[7], "messageID": values[2]]
            )))
        }
        let hasMore = rows.count == batchSize
        return ConnectorSyncBatch(
            documents: rows.map(\.document),
            nextOffset: hasMore ? rows.last?.rowID : nil,
            initialSyncCompleted: !hasMore,
            progressDescription: "Indexed \(rows.count) mail history in this batch"
        )
    }
}

private enum AppleMailStoreLocator {
    static func firstExistingDatabase() -> URL? {
        let mailURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Mail")
        let candidates = ["V11", "V10", "V9", "V8", "V7"].map {
            mailURL.appending(path: "\($0)/MailData/Envelope Index")
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

actor LocalSQLiteReader: LocalSQLiteReading {
    func read(databaseURL: URL, query: String) throws -> String {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            defer { sqlite3_close(database) }
            throw Self.connectorError(for: Self.sqliteMessage(database))
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Self.connectorError(for: Self.sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        var lines: [String] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let values = (0..<Int(sqlite3_column_count(statement))).map { index -> String in
                    guard sqlite3_column_type(statement, Int32(index)) != SQLITE_NULL,
                          let text = sqlite3_column_text(statement, Int32(index))
                    else { return "" }
                    return String(decoding: UnsafeBufferPointer(start: text, count: Int(sqlite3_column_bytes(statement, Int32(index)))), as: UTF8.self)
                }
                lines.append(values.joined(separator: "\u{1F}"))
            case SQLITE_DONE:
                return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
            default:
                throw Self.connectorError(for: Self.sqliteMessage(database))
            }
        }
    }

    nonisolated static func connectorError(for message: String) -> ConnectorError {
        if message.localizedCaseInsensitiveContains("permission denied")
            || message.localizedCaseInsensitiveContains("authorization denied")
            || message.localizedCaseInsensitiveContains("unable to open database")
        {
            return .permissionDenied("MacBrain needs Full Disk Access to read this local library. Enable it in System Settings, then reauthorize.")
        }
        return .sourceUnavailable("This local library could not be read.")
    }

    nonisolated private static func sqliteMessage(_ database: OpaquePointer?) -> String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database."
    }
}

private enum BooksLibraryLocator {
    static func firstExistingDatabase() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary/BKLibrary-1-091020131601.sqlite",
            "Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary/BKLibrary.sqlite",
            "Library/Containers/com.apple.BKAgentService/Data/Documents/iBooks/Books/Metadata.sqlite"
        ].map { home.appending(path: $0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private func localReadError(for source: String, error: Error) -> ConnectorError {
    let nsError = error as NSError
    if nsError.code == NSFileReadNoPermissionError || nsError.domain == NSPOSIXErrorDomain {
        return .permissionDenied("MacBrain needs Full Disk Access to read \(source). Enable it in System Settings, then reauthorize.")
    }
    return .sourceUnavailable("\(source) is unavailable on this Mac.")
}

private func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
