import Foundation

actor LocalSourceRepository {
    private struct Snapshot: Codable {
        static let currentSchemaVersion = 2

        var schemaVersion: Int
        var records: [ConnectorRecord] = []
        var documents: [ConnectorDocument] = []

        init(
            schemaVersion: Int = Self.currentSchemaVersion,
            records: [ConnectorRecord] = [],
            documents: [ConnectorDocument] = []
        ) {
            self.schemaVersion = schemaVersion
            self.records = records
            self.documents = documents
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case records
            case documents
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
            records = try container.decodeIfPresent([ConnectorRecord].self, forKey: .records) ?? []
            documents = try container.decodeIfPresent([ConnectorDocument].self, forKey: .documents) ?? []
        }
    }

    private let fileURL: URL
    private var snapshot: Snapshot

    init(fileURL: URL? = nil) {
        let defaultURL = Self.defaultFileURL()
        let resolvedURL = fileURL ?? defaultURL
        let loadedSnapshot = Self.load(from: resolvedURL)
        self.fileURL = resolvedURL

        if loadedSnapshot.schemaVersion < 1 {
            // Versions before explicit connector consent may contain sources
            // added automatically at launch. Do not retain that indexed data.
            self.snapshot = Snapshot()
            try? Self.persist(self.snapshot, to: resolvedURL)
        } else if loadedSnapshot.schemaVersion < Snapshot.currentSchemaVersion {
            var migratedSnapshot = loadedSnapshot
            migratedSnapshot.schemaVersion = Snapshot.currentSchemaVersion
            for index in migratedSnapshot.records.indices where
                migratedSnapshot.records[index].kind == .browserProfile
                    && migratedSnapshot.records[index].configuration.browserKind == nil
            {
                migratedSnapshot.records[index].status = .paused
                migratedSnapshot.records[index].lastError = "Choose a new Browser profile source before syncing."
                migratedSnapshot.records[index].syncProgress = nil
            }
            self.snapshot = migratedSnapshot
            try? Self.persist(self.snapshot, to: resolvedURL)
        } else {
            self.snapshot = loadedSnapshot
        }
    }

    func allRecords() -> [ConnectorRecord] {
        snapshot.records.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func record(id: UUID) -> ConnectorRecord? {
        snapshot.records.first { $0.id == id }
    }

    func save(_ record: ConnectorRecord) throws {
        if let index = snapshot.records.firstIndex(where: { $0.id == record.id }) {
            snapshot.records[index] = record
        } else {
            snapshot.records.append(record)
        }
        try persist()
    }

    func replaceDocuments(for connectorID: UUID, with documents: [ConnectorDocument]) throws -> Int {
        var seen = Set<String>()
        let uniqueDocuments = documents.filter { seen.insert($0.externalID + $0.contentHash).inserted }
        snapshot.documents.removeAll { $0.connectorID == connectorID }
        snapshot.documents.append(contentsOf: uniqueDocuments)
        try persist()
        return uniqueDocuments.count
    }

    func mergeDocuments(for connectorID: UUID, with documents: [ConnectorDocument]) throws -> Int {
        var documentsByExternalID: [String: ConnectorDocument] = [:]
        for document in documents {
            documentsByExternalID[document.externalID] = document
        }
        let incomingIDs = Set(documentsByExternalID.keys)
        snapshot.documents.removeAll {
            $0.connectorID == connectorID && incomingIDs.contains($0.externalID)
        }
        snapshot.documents.append(contentsOf: documentsByExternalID.values)
        try persist()
        return documentCount(for: connectorID)
    }

    func remove(id: UUID) throws {
        snapshot.records.removeAll { $0.id == id }
        snapshot.documents.removeAll { $0.connectorID == id }
        try persist()
    }

    func search(_ query: String, limit: Int = 5) -> [ConnectorDocument] {
        let tokens = query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
        guard !tokens.isEmpty else { return [] }

        let scoredDocuments: [(document: ConnectorDocument, score: Int)] = snapshot.documents.map { document in
            let haystack = [document.title, document.text, document.sourceLabel].joined(separator: " ").lowercased()
            let score = tokens.reduce(into: 0) { partialResult, token in
                partialResult += haystack.components(separatedBy: token).count - 1
            }
            return (document: document, score: score)
        }

        return scoredDocuments
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1
                    ? (lhs.0.modifiedAt ?? .distantPast) > (rhs.0.modifiedAt ?? .distantPast)
                    : lhs.1 > rhs.1
            }
            .prefix(limit)
            .map(\.document)
    }

    func documentCount(for connectorID: UUID) -> Int {
        snapshot.documents.filter { $0.connectorID == connectorID }.count
    }

    private func persist() throws {
        try Self.persist(snapshot, to: fileURL)
    }

    private static func persist(_ snapshot: Snapshot, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.local.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> Snapshot {
        guard let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder.local.decode(Snapshot.self, from: data) else {
            return Snapshot()
        }
        return snapshot
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBrain", isDirectory: true)
        return directory.appendingPathComponent("local-sources.json")
    }
}

private extension JSONEncoder {
    static var local: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var local: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
