import Foundation

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
        let offset = record.configuration.syncOffset ?? 0
        let cutoff = record.configuration.initialSyncCompleted
            ? record.lastSuccessfulSync.map { Int($0.timeIntervalSinceReferenceDate) }
            : nil
        let cutoffClause = cutoff.map {
            "AND (CASE WHEN m.date > 1000000000000 THEN m.date / 1000000000 ELSE m.date END) > \($0)"
        } ?? ""
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
        ORDER BY m.date DESC
        LIMIT \(batchSize) OFFSET \(offset);
        """
        let output = try await reader.read(databaseURL: databaseURL, query: query)
        let rows = output.split(whereSeparator: \.isNewline)
        let documents: [ConnectorDocument] = rows.compactMap { row -> ConnectorDocument? in
            let parts = row.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6 else { return nil }
            return ConnectorDocument(
                connectorID: record.id,
                externalID: parts[1].isEmpty ? parts[0] : parts[1],
                title: parts[2].isEmpty ? "Message" : "Message with \(parts[2])",
                text: parts[3],
                sourceLabel: parts[5].isEmpty ? "Messages" : "Messages: \(parts[5])",
                metadata: ["senderOrHandle": parts[2], "date": parts[4], "chat": parts[5]]
            )
        }
        let hasMore = documents.count == batchSize
        let nextOffset = hasMore ? offset + documents.count : nil
        let phase = record.configuration.initialSyncCompleted ? "new messages" : "message history"
        return ConnectorSyncBatch(
            documents: documents,
            nextOffset: nextOffset,
            initialSyncCompleted: record.configuration.initialSyncCompleted || !hasMore,
            progressDescription: "Indexed \(documents.count) \(phase) · \(offset + documents.count) total"
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

actor LocalSQLiteReader: LocalSQLiteReading {
    func read(databaseURL: URL, query: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\u{1F}", databaseURL.path, query]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ConnectorError.sourceUnavailable("The local SQLite reader is unavailable on this Mac.")
        }
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            if message.localizedCaseInsensitiveContains("permission denied") || message.localizedCaseInsensitiveContains("unable to open database") {
                throw ConnectorError.permissionDenied("MacBrain needs Full Disk Access to read this local library. Enable it in System Settings, then reauthorize.")
            }
            throw ConnectorError.sourceUnavailable("This local library could not be read.")
        }
        return result
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
