import CryptoKit
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
    private let database: MacBrainDatabase?
    private var snapshot: Snapshot
    private var hasBootstrappedDatabase = false
    private var transientIndexHealth: [UUID: ConnectorIndexHealth] = [:]
    /// A connector generation is published only after its documents, chunks,
    /// and health row commit together. Keep that verified snapshot in memory
    /// so questions never queue behind a new generation that is still writing.
    private var verifiedIndexHealthCache: [UUID: ConnectorIndexHealth] = [:]
    /// Batched connectors build their next generation in memory and publish it
    /// atomically only when the final batch succeeds. SQLite remains the live,
    /// queryable authority until that commit.
    private var pendingDocumentGenerations: [UUID: [String: ConnectorDocument]] = [:]
    /// Blocks late async connector work from recreating a source that was deleted
    /// while its sync was still in flight.
    private var removedRecordIDs = Set<UUID>()

    init(fileURL: URL? = nil, database: MacBrainDatabase? = nil) {
        let defaultURL = Self.defaultFileURL()
        let resolvedURL = fileURL ?? defaultURL
        let loadedSnapshot = Self.load(from: resolvedURL)
        self.fileURL = resolvedURL
        self.database = database ?? (fileURL == nil ? try? MacBrainDatabase() : nil)

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

    func bootstrap() async throws {
        guard let database else { return }
        try await database.migrate()

        let legacyImportIsComplete = try await database.metadata(
            "legacy_source_import_complete"
        ) == "true"
        if !legacyImportIsComplete {
            let legacyRecords = snapshot.records
            let legacyDocumentsBySource = Dictionary(
                grouping: snapshot.documents,
                by: \.connectorID
            )
            let existingDatabaseRecords = Dictionary(
                uniqueKeysWithValues: try await database.allConnectorRecords().map { ($0.id, $0) }
            )

            for legacyRecord in legacyRecords {
                let legacySourceDocuments = legacyDocumentsBySource[legacyRecord.id] ?? []
                let verifiedHealth = try await database.verifiedIndexHealth(
                    sourceID: legacyRecord.id
                )
                let legacyContentRevision = legacySourceDocuments.isEmpty
                    ? nil
                    : Self.contentRevision(for: legacySourceDocuments)
                let verifiedGenerationMatchesLegacy = existingDatabaseRecords[legacyRecord.id] != nil
                    && verifiedHealth != nil
                    && (
                        legacySourceDocuments.isEmpty
                            || (
                                verifiedHealth?.documentCount == legacySourceDocuments.count
                                    && verifiedHealth?.contentRevision == legacyContentRevision
                            )
                    )

                if !verifiedGenerationMatchesLegacy {
                    // A partially completed migration may already have source
                    // documents in SQLite but no verified health row. Hydrate
                    // only that one source when it actually needs repair.
                    let importDocuments = if legacySourceDocuments.isEmpty,
                                             existingDatabaseRecords[legacyRecord.id] != nil {
                        try await database.documents(sourceID: legacyRecord.id)
                            .map(ConnectorDocument.init)
                    } else {
                        legacySourceDocuments
                    }
                    let hasCompletedInitialSync = legacyRecord.configuration.initialSyncCompleted
                        || legacyRecord.status == .ready
                        || legacyRecord.lastSuccessfulSync != nil
                    let health = ConnectorIndexHealth(
                        sourceID: legacyRecord.id,
                        documentCount: importDocuments.count,
                        chunkCount: 0,
                        contentRevision: Self.contentRevision(for: importDocuments),
                        initialSyncCompleted: hasCompletedInitialSync,
                        lastSuccessfulSync: legacyRecord.lastSuccessfulSync,
                        lastVerifiedAt: hasCompletedInitialSync ? .now : nil,
                        lastError: legacyRecord.lastError
                    )
                    _ = try await database.commitSourceGeneration(
                        record: legacyRecord,
                        documents: importDocuments.map(StoredDocument.init),
                        health: health
                    )
                } else {
                    var persistedRecord = legacyRecord
                    persistedRecord.documentCount = verifiedHealth?.documentCount
                        ?? legacySourceDocuments.count
                    try await database.save(connectorRecord: persistedRecord)
                }
            }
        }

        try await removeDuplicateBrowserProfiles(from: database)

        let hydratedRecords = try await database.allConnectorRecords()
        // SQLite is the document authority after migration. Keeping only the
        // small connector records here prevents every launch from decoding the
        // entire local corpus before recovery and query services can start.
        snapshot = Snapshot(records: hydratedRecords, documents: [])
        // `source_index_state` is written in the same transaction as its
        // documents and chunks. Reading those committed rows is sufficient at
        // launch; re-counting every source here can otherwise block the first
        // question behind a large connector refresh.
        verifiedIndexHealthCache = try await database.allIndexHealth().filter {
            $0.value.isSearchable
        }

        // This marker is intentionally last: a partially imported source set
        // is retried idempotently on the next launch.
        if !legacyImportIsComplete {
            try await database.setMetadata("legacy_source_import_complete", value: "true")
        }
        hasBootstrappedDatabase = true
    }

    private func removeDuplicateBrowserProfiles(from database: MacBrainDatabase) async throws {
        let records = try await database.allConnectorRecords()
        let healthBySourceID = try await database.allIndexHealth()
        var recordsByProfile: [String: [ConnectorRecord]] = [:]

        for record in records where record.kind == .browserProfile {
            guard let browserKind = record.configuration.browserKind,
                  let localPath = record.configuration.localPath,
                  !localPath.isEmpty else {
                continue
            }
            let standardizedPath = URL(fileURLWithPath: localPath).standardizedFileURL.path
            let key = browserKind.rawValue + "\u{1F}" + standardizedPath
            recordsByProfile[key, default: []].append(record)
        }

        for duplicates in recordsByProfile.values where duplicates.count > 1 {
            let ranked = duplicates.sorted { lhs, rhs in
                let lhsVerified = healthBySourceID[lhs.id]?.isSearchable == true
                let rhsVerified = healthBySourceID[rhs.id]?.isSearchable == true
                if lhsVerified != rhsVerified { return lhsVerified }

                let lhsDate = healthBySourceID[lhs.id]?.lastVerifiedAt
                    ?? lhs.lastSuccessfulSync
                    ?? .distantPast
                let rhsDate = healthBySourceID[rhs.id]?.lastVerifiedAt
                    ?? rhs.lastSuccessfulSync
                    ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            for duplicate in ranked.dropFirst() {
                try await database.remove(sourceID: duplicate.id)
            }
        }
    }

    func indexHealth(for connectorID: UUID) async -> ConnectorIndexHealth? {
        guard let database else { return transientIndexHealth[connectorID] }
        if let cached = verifiedIndexHealthCache[connectorID] { return cached }
        return try? await database.indexHealth(sourceID: connectorID)
    }

    func verifiedIndexHealth(for connectorID: UUID) async -> ConnectorIndexHealth? {
        guard let database else {
            return transientIndexHealth[connectorID]?.isSearchable == true
                ? transientIndexHealth[connectorID]
                : nil
        }
        if let cached = verifiedIndexHealthCache[connectorID] { return cached }
        return try? await database.verifiedIndexHealth(sourceID: connectorID)
    }

    func sourceHealth() async -> [UUID: ConnectorIndexHealth] {
        guard database != nil else { return transientIndexHealth }
        return verifiedIndexHealthCache
    }

    func executeConnectorQuery(
        _ operation: ConnectorQueryOperation,
        scope: Set<SourceConnectorKind>?,
        now: Date
    ) async -> ConnectorQueryExecution {
        await executeConnectorQuery(operation, scope: scope, now: now, retriesRemaining: 1)
    }

    private func executeConnectorQuery(
        _ operation: ConnectorQueryOperation,
        scope: Set<SourceConnectorKind>?,
        now: Date,
        retriesRemaining: Int
    ) async -> ConnectorQueryExecution {
        let effectiveScope = Self.effectiveScope(for: operation, requestedScope: scope)
        let matchingRecords = snapshot.records.filter { record in
            !removedRecordIDs.contains(record.id)
                && (effectiveScope == nil || effectiveScope?.contains(record.kind) == true)
        }
        guard !matchingRecords.isEmpty else {
            return .notConnected(requestedKinds: effectiveScope ?? [])
        }

        let authorizedRecords = matchingRecords.filter { $0.status != .needsAuthorization }
        guard !authorizedRecords.isEmpty else {
            return .permissionNeeded(sourceKinds: Set(matchingRecords.map(\.kind)))
        }

        let verifiedHealth = await sourceHealth()
        let eligibleRecords = authorizedRecords.filter { verifiedHealth[$0.id]?.isSearchable == true }
        guard !eligibleRecords.isEmpty else {
            return .indexUnavailable(sourceKinds: Set(authorizedRecords.map(\.kind)))
        }

        let eligibleIDs = Set(eligibleRecords.map(\.id))
        let eligibleKinds = Set(eligibleRecords.map(\.kind))
        let result: ConnectorQueryResult
        do {
            if operation == .count {
                result = ConnectorQueryResult(
                    operation: operation,
                    totalCount: eligibleIDs.reduce(into: 0) { total, sourceID in
                        total += verifiedHealth[sourceID]?.documentCount ?? 0
                    },
                    documents: [],
                    capturedAt: now
                )
            } else if let database {
                result = try await Self.databaseResult(
                    operation: operation,
                    sourceIDs: eligibleIDs,
                    now: now,
                    database: database
                )
            } else {
                result = Self.inMemoryResult(
                    operation: operation,
                    sourceIDs: eligibleIDs,
                    documents: snapshot.documents,
                    now: now
                )
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        // Repository actor methods are reentrant while awaiting SQLite. If a
        // source is removed or loses authorization during the query, discard
        // that result and resolve the operation once more against current state.
        let currentEligibleIDs = Set(snapshot.records.compactMap { record -> UUID? in
            guard eligibleIDs.contains(record.id),
                  !removedRecordIDs.contains(record.id),
                  record.status != .needsAuthorization else {
                return nil
            }
            return record.id
        })
        guard currentEligibleIDs == eligibleIDs else {
            guard retriesRemaining > 0 else {
                let currentKinds = Set(snapshot.records.compactMap { record in
                    effectiveScope == nil || effectiveScope?.contains(record.kind) == true
                        ? record.kind
                        : nil
                })
                return currentKinds.isEmpty
                    ? .notConnected(requestedKinds: effectiveScope ?? [])
                    : .indexUnavailable(sourceKinds: currentKinds)
            }
            return await executeConnectorQuery(
                operation,
                scope: scope,
                now: now,
                retriesRemaining: retriesRemaining - 1
            )
        }

        return .result(result, sourceKinds: eligibleKinds)
    }

    func documents(for connectorID: UUID) async -> [ConnectorDocument] {
        (try? await sourceDocuments(for: connectorID)) ?? []
    }

    private static func effectiveScope(
        for operation: ConnectorQueryOperation,
        requestedScope: Set<SourceConnectorKind>?
    ) -> Set<SourceConnectorKind>? {
        switch operation {
        case .nextEvent:
            return requestedScope.map { $0.intersection([.calendar]) } ?? [.calendar]
        case .firstDueReminder:
            return requestedScope.map { $0.intersection([.reminders]) } ?? [.reminders]
        case .count, .newest, .oldest:
            return requestedScope
        }
    }

    private static func databaseResult(
        operation: ConnectorQueryOperation,
        sourceIDs: Set<UUID>,
        now: Date,
        database: MacBrainDatabase
    ) async throws -> ConnectorQueryResult {
        let totalCount: Int?
        let documents: [StoredDocument]
        switch operation {
        case .count:
            totalCount = try await database.documentCount(sourceIDs: sourceIDs)
            documents = []
        case .newest(let limit):
            totalCount = nil
            documents = try await database.documents(
                sourceIDs: sourceIDs,
                ascending: false,
                limit: limit
            )
        case .oldest(let limit):
            totalCount = nil
            documents = try await database.documents(
                sourceIDs: sourceIDs,
                ascending: true,
                limit: limit
            )
        case .nextEvent:
            totalCount = nil
            documents = try await database.documents(
                sourceIDs: sourceIDs,
                metadataDateKey: "start",
                after: now,
                metadataEquals: [:],
                ascending: true,
                limit: 1
            )
        case .firstDueReminder:
            totalCount = nil
            documents = try await database.documents(
                sourceIDs: sourceIDs,
                metadataDateKey: "due",
                after: nil,
                metadataEquals: ["completed": "false"],
                ascending: true,
                limit: 1
            )
        }
        return ConnectorQueryResult(
            operation: operation,
            totalCount: totalCount,
            documents: documents.map(ConnectorDocument.init),
            capturedAt: now
        )
    }

    private static func inMemoryResult(
        operation: ConnectorQueryOperation,
        sourceIDs: Set<UUID>,
        documents: [ConnectorDocument],
        now: Date
    ) -> ConnectorQueryResult {
        let eligible = documents.filter { sourceIDs.contains($0.connectorID) }
        let totalCount: Int?
        let selected: [ConnectorDocument]
        switch operation {
        case .count:
            totalCount = eligible.count
            selected = []
        case .newest(let limit):
            totalCount = nil
            selected = Array(eligible.sorted(by: Self.newestFirst).prefix(Self.boundedLimit(limit)))
        case .oldest(let limit):
            totalCount = nil
            selected = Array(eligible.sorted(by: Self.oldestFirst).prefix(Self.boundedLimit(limit)))
        case .nextEvent:
            totalCount = nil
            selected = Array(
                eligible
                    .compactMap { document -> (ConnectorDocument, Date)? in
                        guard let date = Self.metadataDate(document.metadata["start"]), date > now else {
                            return nil
                        }
                        return (document, date)
                    }
                    .sorted { $0.1 < $1.1 }
                    .prefix(1)
                    .map(\.0)
            )
        case .firstDueReminder:
            totalCount = nil
            selected = Array(
                eligible
                    .compactMap { document -> (ConnectorDocument, Date)? in
                        guard document.metadata["completed"] == "false",
                              let date = Self.metadataDate(document.metadata["due"]) else {
                            return nil
                        }
                        return (document, date)
                    }
                    .sorted { $0.1 < $1.1 }
                    .prefix(1)
                    .map(\.0)
            )
        }
        return ConnectorQueryResult(
            operation: operation,
            totalCount: totalCount,
            documents: selected,
            capturedAt: now
        )
    }

    private static func boundedLimit(_ limit: Int) -> Int {
        min(max(limit, 1), 100)
    }

    private static func newestFirst(_ lhs: ConnectorDocument, _ rhs: ConnectorDocument) -> Bool {
        let left = lhs.modifiedAt ?? lhs.createdAt ?? .distantPast
        let right = rhs.modifiedAt ?? rhs.createdAt ?? .distantPast
        return left == right ? lhs.externalID < rhs.externalID : left > right
    }

    private static func oldestFirst(_ lhs: ConnectorDocument, _ rhs: ConnectorDocument) -> Bool {
        let left = lhs.modifiedAt ?? lhs.createdAt ?? .distantPast
        let right = rhs.modifiedAt ?? rhs.createdAt ?? .distantPast
        return left == right ? lhs.externalID < rhs.externalID : left < right
    }

    private static func metadataDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return try? Date(value, strategy: .iso8601)
    }

    func reconciledDocuments(
        for connectorID: UUID,
        changedDocuments: [ConnectorDocument],
        presentExternalIDs: [String]
    ) async throws -> [ConnectorDocument] {
        try ensureSourceHasNotBeenRemoved(connectorID)
        let existingDocuments = try await sourceDocuments(for: connectorID)
        try ensureSourceHasNotBeenRemoved(connectorID)
        let existingByExternalID = Dictionary(
            uniqueKeysWithValues: existingDocuments.map { ($0.externalID, $0) }
        )
        let changedByExternalID = Dictionary(
            uniqueKeysWithValues: changedDocuments.map { ($0.externalID, $0) }
        )
        return presentExternalIDs.compactMap { externalID in
            changedByExternalID[externalID] ?? existingByExternalID[externalID]
        }
    }

    func commitSourceGeneration(
        record: ConnectorRecord,
        documents: [ConnectorDocument]
    ) async throws -> ConnectorIndexHealth {
        try ensureSourceHasNotBeenRemoved(record.id)
        let cachedDocuments = replacementDocuments(
            for: record.id,
            incoming: documents,
            existing: database == nil
                ? snapshot.documents.filter { $0.connectorID == record.id }
                : []
        )
        let timestamp = record.lastSuccessfulSync ?? .now
        var health = ConnectorIndexHealth(
            sourceID: record.id,
            documentCount: cachedDocuments.count,
            chunkCount: cachedDocuments.count,
            contentRevision: Self.contentRevision(for: cachedDocuments),
            initialSyncCompleted: record.configuration.initialSyncCompleted,
            lastSuccessfulSync: record.lastSuccessfulSync,
            lastVerifiedAt: timestamp,
            lastError: record.lastError
        )

        if let database {
            health = try await database.commitSourceGeneration(
                record: record,
                documents: cachedDocuments.map(StoredDocument.init),
                health: health
            )
            // Actor reentrancy: deletion can run while SQLite is committing.
            // Never restore in-memory state after a concurrent remove.
            try ensureSourceHasNotBeenRemoved(record.id)
            verifiedIndexHealthCache[record.id] = health
        } else {
            transientIndexHealth[record.id] = health
        }

        var committedRecord = record
        committedRecord.documentCount = health.documentCount
        if let index = snapshot.records.firstIndex(where: { $0.id == record.id }) {
            snapshot.records[index] = committedRecord
        } else {
            snapshot.records.append(committedRecord)
        }
        pendingDocumentGenerations[record.id] = nil
        if database == nil {
            snapshot.documents.removeAll { $0.connectorID == record.id }
            snapshot.documents.append(contentsOf: cachedDocuments)
        }
        try persist()
        return health
    }

    func commitReconciledSourceGeneration(
        record: ConnectorRecord,
        changedDocuments: [ConnectorDocument],
        presentExternalIDs: [String]
    ) async throws -> ConnectorIndexHealth {
        try ensureSourceHasNotBeenRemoved(record.id)
        guard let database else {
            let reconciled = try await reconciledDocuments(
                for: record.id,
                changedDocuments: changedDocuments,
                presentExternalIDs: presentExternalIDs
            )
            return try await commitSourceGeneration(record: record, documents: reconciled)
        }

        let timestamp = record.lastSuccessfulSync ?? .now
        let proposedHealth = ConnectorIndexHealth(
            sourceID: record.id,
            initialSyncCompleted: record.configuration.initialSyncCompleted,
            lastSuccessfulSync: record.lastSuccessfulSync,
            lastVerifiedAt: timestamp,
            lastError: record.lastError
        )
        let health = try await database.commitReconciledSourceGeneration(
            record: record,
            changedDocuments: changedDocuments.map(StoredDocument.init),
            presentExternalIDs: presentExternalIDs,
            health: proposedHealth
        )
        // Actor reentrancy: a user can remove the source while SQLite commits.
        try ensureSourceHasNotBeenRemoved(record.id)
        verifiedIndexHealthCache[record.id] = health

        var committedRecord = record
        committedRecord.documentCount = health.documentCount
        if let index = snapshot.records.firstIndex(where: { $0.id == record.id }) {
            snapshot.records[index] = committedRecord
        } else {
            snapshot.records.append(committedRecord)
        }
        pendingDocumentGenerations[record.id] = nil
        try persist()
        return health
    }

    func allRecords() -> [ConnectorRecord] {
        snapshot.records.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func record(id: UUID) -> ConnectorRecord? {
        snapshot.records.first { $0.id == id }
    }

    func save(_ record: ConnectorRecord) async throws {
        guard !removedRecordIDs.contains(record.id) else {
            throw ConnectorError.sourceUnavailable("This source no longer exists.")
        }
        if let index = snapshot.records.firstIndex(where: { $0.id == record.id }) {
            snapshot.records[index] = record
        } else {
            snapshot.records.append(record)
        }
        // Photos and other batched connectors update their progress after every
        // page. Persisting the entire document snapshot for each `.syncing`
        // update makes an incremental sync quadratic. The database record still
        // receives every update; write the recovery snapshot at terminal states.
        if record.status != .syncing {
            try persist()
        }
        if let database {
            try await database.save(connectorRecord: record)
        }
    }

    func replaceDocuments(for connectorID: UUID, with documents: [ConnectorDocument]) async throws -> Int {
        try ensureSourceHasNotBeenRemoved(connectorID)
        let existingDocuments = try await sourceDocuments(for: connectorID)
        try ensureSourceHasNotBeenRemoved(connectorID)
        let cachedDocuments = replacementDocuments(
            for: connectorID,
            incoming: documents,
            existing: existingDocuments
        )
        let changed = existingDocuments.count != cachedDocuments.count
            || zip(existingDocuments.sorted(by: { $0.externalID < $1.externalID }), cachedDocuments.sorted(by: { $0.externalID < $1.externalID })).contains {
                $0.externalID != $1.externalID || !$0.matchesCacheEntry(for: $1)
            }
        guard changed else {
            if let database {
                let indexIsIntact = try await database.sourceIndexIsIntact(
                    sourceID: connectorID,
                    expectedDocumentCount: cachedDocuments.count
                )
                if !indexIsIntact {
                    try await database.replaceSourceDocuments(
                        sourceID: connectorID,
                        documents: cachedDocuments.map(StoredDocument.init)
                    )
                }
            }
            return existingDocuments.count
        }

        if let database {
            try await database.replaceSourceDocuments(
                sourceID: connectorID,
                documents: cachedDocuments.map(StoredDocument.init)
            )
            try ensureSourceHasNotBeenRemoved(connectorID)
            pendingDocumentGenerations[connectorID] = nil
        } else {
            snapshot.documents.removeAll { $0.connectorID == connectorID }
            snapshot.documents.append(contentsOf: cachedDocuments)
            try persist()
        }
        return cachedDocuments.count
    }

    func changedExternalIDs(for connectorID: UUID, incoming documents: [ConnectorDocument]) async -> Set<String> {
        var seen = Set<String>()
        let unique = documents.filter { seen.insert($0.externalID + $0.contentHash).inserted }
        let existingDocuments = (try? await sourceDocuments(for: connectorID)) ?? []
        let existing = Dictionary(
            uniqueKeysWithValues: existingDocuments.map { ($0.externalID, $0) }
        )
        return Set(unique.compactMap { document in
            guard let cached = existing[document.externalID], cached.matchesCacheEntry(for: document) else {
                return document.externalID
            }
            return nil
        })
    }

    func mergeDocuments(
        for connectorID: UUID,
        with documents: [ConnectorDocument],
        updateSearchIndex: Bool = true
    ) async throws -> Int {
        try ensureSourceHasNotBeenRemoved(connectorID)
        let existingDocuments = try await sourceDocuments(for: connectorID)
        try ensureSourceHasNotBeenRemoved(connectorID)
        var documentsByExternalID: [String: ConnectorDocument] = [:]
        for document in documents {
            documentsByExternalID[document.externalID] = document
        }
        let existingByExternalID = Dictionary(
            uniqueKeysWithValues: existingDocuments.map { ($0.externalID, $0) }
        )
        let incomingIDs = Set(documentsByExternalID.keys)
        let cachedDocuments = documentsByExternalID.values.map { incoming in
            guard let existing = existingByExternalID[incoming.externalID], existing.matchesCacheEntry(for: incoming) else {
                return incoming
            }
            return existing
        }
        let changed = cachedDocuments.contains { incoming in
            guard let existing = existingByExternalID[incoming.externalID] else { return true }
            return !existing.matchesCacheEntry(for: incoming)
        }
        guard changed else { return await documentCount(for: connectorID) }
        if let database {
            if updateSearchIndex {
                try await database.upsertSourceDocuments(
                    sourceID: connectorID,
                    documents: cachedDocuments.map(StoredDocument.init)
                )
                try ensureSourceHasNotBeenRemoved(connectorID)
                return await documentCount(for: connectorID)
            }

            var pending = existingByExternalID
            for document in cachedDocuments {
                pending[document.externalID] = document
            }
            pendingDocumentGenerations[connectorID] = pending
            return pending.count
        }

        snapshot.documents.removeAll {
            $0.connectorID == connectorID && incomingIDs.contains($0.externalID)
        }
        snapshot.documents.append(contentsOf: cachedDocuments)
        try persist()
        return await documentCount(for: connectorID)
    }

    func refreshSearchIndex(for connectorID: UUID) async throws {
        try ensureSourceHasNotBeenRemoved(connectorID)
        if let database {
            let documents = try await sourceDocuments(for: connectorID)
            try ensureSourceHasNotBeenRemoved(connectorID)
            try await database.replaceSourceDocuments(
                sourceID: connectorID,
                documents: documents.map(StoredDocument.init)
            )
        }
    }

    func reconcileDocuments(
        for connectorID: UUID,
        changedDocuments: [ConnectorDocument],
        presentExternalIDs: [String]
    ) async throws -> Int {
        try ensureSourceHasNotBeenRemoved(connectorID)
        let existingDocuments = try await sourceDocuments(for: connectorID)
        try ensureSourceHasNotBeenRemoved(connectorID)
        let existingByExternalID = Dictionary(
            uniqueKeysWithValues: existingDocuments.map { ($0.externalID, $0) }
        )
        let changedByExternalID = Dictionary(
            uniqueKeysWithValues: changedDocuments.map { ($0.externalID, $0) }
        )
        let reconciled = presentExternalIDs.compactMap { externalID in
            changedByExternalID[externalID] ?? existingByExternalID[externalID]
        }
        let existing = existingDocuments
        let changed = existing.count != reconciled.count
            || zip(existing.sorted { $0.externalID < $1.externalID }, reconciled.sorted { $0.externalID < $1.externalID }).contains {
                $0.externalID != $1.externalID || !$0.matchesCacheEntry(for: $1)
            }
        guard changed else { return existing.count }

        if let database {
            try await database.replaceSourceDocuments(
                sourceID: connectorID,
                documents: reconciled.map(StoredDocument.init)
            )
            try ensureSourceHasNotBeenRemoved(connectorID)
            pendingDocumentGenerations[connectorID] = nil
        } else {
            snapshot.documents.removeAll { $0.connectorID == connectorID }
            snapshot.documents.append(contentsOf: reconciled)
            try persist()
        }
        return reconciled.count
    }

    func indexedChunkIDs(for connectorID: UUID, externalIDs: Set<String>) async -> [UUID] {
        guard let database else { return [] }
        return (try? await database.chunkIDs(sourceID: connectorID, documentExternalIDs: externalIDs)) ?? []
    }

    func remove(id: UUID) async throws {
        removedRecordIDs.insert(id)
        transientIndexHealth[id] = nil
        verifiedIndexHealthCache[id] = nil
        pendingDocumentGenerations[id] = nil
        snapshot.records.removeAll { $0.id == id }
        snapshot.documents.removeAll { $0.connectorID == id }
        try persist()
        if let database {
            try await database.remove(sourceID: id)
        }
    }

    func search(
        _ query: String,
        limit: Int = 5,
        sourceKinds: Set<SourceConnectorKind>? = nil
    ) async -> [ConnectorDocument] {
        let sourceIDs = await eligibleSourceIDs(sourceKinds: sourceKinds)
        guard !sourceIDs.isEmpty else { return [] }
        if let database, let documents = try? await database.searchDocuments(
            matching: query,
            limit: limit,
            sourceIDs: sourceIDs
        ) {
            return documents.map(ConnectorDocument.init)
        }

        let tokens = query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
        guard !tokens.isEmpty else { return [] }

        let scoredDocuments: [(document: ConnectorDocument, score: Int)] = snapshot.documents
            .filter { sourceIDs.contains($0.connectorID) }
            .map { document in
                let haystack = [document.title, document.text, document.sourceLabel]
                    .joined(separator: " ")
                    .lowercased()
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

    func searchEvidence(
        _ query: String,
        using provider: any InferenceProvider,
        embeddingModel: String,
        limit: Int = 6,
        sourceKinds: Set<SourceConnectorKind>? = nil
    ) async -> EvidenceSearchResult {
        let sourceIDs = await eligibleSourceIDs(sourceKinds: sourceKinds)
        guard !sourceIDs.isEmpty else { return .empty }
        if let database {
            return (try? await HybridEvidenceRetriever(
                database: database,
                provider: provider,
                embeddingModel: embeddingModel
            ).search(query, limit: limit, sourceIDs: sourceIDs)) ?? .empty
        }

        let documents = await search(query, limit: max(limit, snapshot.documents.count))
            .filter { sourceIDs.contains($0.connectorID) }
            .prefix(limit)
        let evidence = documents.enumerated().map { index, document in
            let sourceType = record(id: document.connectorID)?.kind.rawValue ?? "local"
            let location = CitationSourceLocation.resolve(
                sourceType: sourceType,
                externalID: document.externalID,
                metadata: document.metadata
            )
            return RetrievalEvidence(
                citationID: "S\(index + 1)", chunkID: UUID(), sourceTitle: document.title,
                sourceType: sourceType,
                sourcePath: location.reference,
                sourceDate: document.modifiedAt ?? document.createdAt,
                excerpt: String(document.text.prefix(1_500)), startOffset: 0,
                endOffset: min(document.text.utf16.count, 1_500), pageNumber: nil,
                score: 1 / Double(index + 1),
                sourceURL: location.url
            )
        }
        return EvidenceSearchResult(evidence: evidence, isLowConfidence: evidence.isEmpty)
    }

    /// Returns exact lexical candidates without waiting for Ollama or querying
    /// the vector/graph indexes. Ambiguous prompts use this as a cheap,
    /// deterministic activation gate before hybrid retrieval.
    func searchLexicalEvidence(
        _ query: String,
        limit: Int = 6,
        sourceKinds: Set<SourceConnectorKind>? = nil
    ) async -> EvidenceSearchResult {
        let sourceIDs = await eligibleSourceIDs(sourceKinds: sourceKinds)
        guard !sourceIDs.isEmpty else { return .empty }
        if let database {
            return (try? await HybridEvidenceRetriever(database: database).searchLexical(
                query,
                limit: limit,
                sourceIDs: sourceIDs
            )) ?? .empty
        }

        let documents = await search(query, limit: max(limit, snapshot.documents.count))
            .filter { sourceIDs.contains($0.connectorID) }
            .prefix(limit)
        let evidence = documents.enumerated().map { index, document in
            let sourceType = record(id: document.connectorID)?.kind.rawValue ?? "local"
            let location = CitationSourceLocation.resolve(
                sourceType: sourceType,
                externalID: document.externalID,
                metadata: document.metadata
            )
            return RetrievalEvidence(
                citationID: "S\(index + 1)", chunkID: UUID(), sourceTitle: document.title,
                sourceType: sourceType,
                sourcePath: location.reference,
                sourceDate: document.modifiedAt ?? document.createdAt,
                excerpt: String(document.text.prefix(1_500)), startOffset: 0,
                endOffset: min(document.text.utf16.count, 1_500), pageNumber: nil,
                score: 1 / Double(index + 1),
                sourceURL: location.url
            )
        }
        return EvidenceSearchResult(evidence: evidence, isLowConfidence: evidence.isEmpty)
    }

    func documentCount(for connectorID: UUID) async -> Int {
        if let pending = pendingDocumentGenerations[connectorID] {
            return pending.count
        }
        guard !removedRecordIDs.contains(connectorID) else { return 0 }
        if let database {
            let count = try? await database.documentCount(sourceIDs: [connectorID])
            guard !removedRecordIDs.contains(connectorID) else { return 0 }
            return count ?? 0
        }
        return snapshot.documents.filter { $0.connectorID == connectorID }.count
    }

    func currentSourceRevision() async -> String {
        if let database,
           let state = try? await database.sourceRevisionState() {
            let accessMaterial = state.records
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { record in
                    [
                        record.id.uuidString,
                        record.kind.rawValue,
                        record.status.rawValue,
                        record.displayName,
                        record.configuration.initialSyncCompleted.description,
                    ].joined(separator: "|")
                }
                .joined(separator: "\n")
            let indexMaterial = state.health
                .sorted { $0.sourceID.uuidString < $1.sourceID.uuidString }
                .map { health in
                    [
                        health.sourceID.uuidString,
                        health.documentCount.description,
                        health.chunkCount.description,
                        health.contentRevision,
                        health.initialSyncCompleted.description,
                        health.isSearchable.description,
                    ].joined(separator: "|")
                }
                .joined(separator: "\n")
            return Self.revisionDigest(
                "access\n\(accessMaterial)\nverified-index\n\(indexMaterial)"
            )
        }

        let accessMaterial = snapshot.records
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.kind.rawValue)|\($0.status.rawValue)" }
            .joined(separator: "\n")
        let documentMaterial = snapshot.documents
            .sorted { lhs, rhs in
                (lhs.connectorID.uuidString, lhs.externalID) < (rhs.connectorID.uuidString, rhs.externalID)
            }
            .map { document in
                let metadata = document.metadata
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "&")
                let modifiedAt = document.modifiedAt?.timeIntervalSince1970.description ?? ""
                return "\(document.connectorID.uuidString)|\(document.externalID)|\(document.contentHash)|\(modifiedAt)|\(metadata)"
            }
            .joined(separator: "\n")
        let material = "access\n\(accessMaterial)\ndocuments\n\(documentMaterial)"
        return Self.revisionDigest(material)
    }

    private func eligibleSourceIDs(sourceKinds: Set<SourceConnectorKind>?) async -> Set<UUID> {
        let verifiedHealth = await sourceHealth()
        return Set(snapshot.records.lazy.filter { record in
            record.status != .needsAuthorization
                && verifiedHealth[record.id]?.isSearchable == true
                && (sourceKinds == nil || sourceKinds?.contains(record.kind) == true)
        }.map(\.id))
    }

    private func persist() throws {
        if database != nil, hasBootstrappedDatabase {
            return
        }
        try Self.persist(snapshot, to: fileURL)
    }

    private func ensureSourceHasNotBeenRemoved(_ connectorID: UUID) throws {
        guard !removedRecordIDs.contains(connectorID) else {
            throw ConnectorError.sourceUnavailable("This source no longer exists.")
        }
    }

    private func sourceDocuments(for connectorID: UUID) async throws -> [ConnectorDocument] {
        try ensureSourceHasNotBeenRemoved(connectorID)
        if let pending = pendingDocumentGenerations[connectorID] {
            return pending.values.sorted { $0.externalID < $1.externalID }
        }
        guard let database else {
            return snapshot.documents.filter { $0.connectorID == connectorID }
        }
        let documents = try await database.documents(sourceID: connectorID)
            .map(ConnectorDocument.init)
        // Actor reentrancy: deletion can run while SQLite is reading.
        try ensureSourceHasNotBeenRemoved(connectorID)
        return documents
    }

    private func replacementDocuments(
        for connectorID: UUID,
        incoming documents: [ConnectorDocument],
        existing existingDocuments: [ConnectorDocument]
    ) -> [ConnectorDocument] {
        var seenExternalIDs = Set<String>()
        let uniqueDocuments = documents.filter {
            seenExternalIDs.insert($0.externalID).inserted
        }
        let existingByExternalID = Dictionary(
            uniqueKeysWithValues: existingDocuments.map { ($0.externalID, $0) }
        )
        return uniqueDocuments.map { incoming in
            guard let existing = existingByExternalID[incoming.externalID],
                  existing.matchesCacheEntry(for: incoming) else {
                return incoming
            }
            return existing
        }
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

    private static func contentRevision(for documents: [ConnectorDocument]) -> String {
        SourceContentRevision.digest(documents.map {
            SourceContentRevisionEntry(
                externalID: $0.externalID,
                contentHash: $0.contentHash,
                createdAt: $0.createdAt,
                modifiedAt: $0.modifiedAt,
                metadata: $0.metadata
            )
        })
    }

    private static func revisionDigest(_ material: String) -> String {
        SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
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

private extension StoredDocument {
    init(_ document: ConnectorDocument) {
        self.init(
            id: document.id,
            sourceID: document.connectorID,
            externalID: document.externalID,
            title: document.title,
            text: document.text,
            sourceLabel: document.sourceLabel,
            createdAt: document.createdAt,
            modifiedAt: document.modifiedAt,
            metadata: document.metadata
        )
    }
}

private extension ConnectorDocument {
    init(_ document: StoredDocument) {
        self.init(
            id: document.id,
            connectorID: document.sourceID,
            externalID: document.externalID,
            title: document.title,
            text: document.text,
            sourceLabel: document.sourceLabel,
            createdAt: document.createdAt,
            modifiedAt: document.modifiedAt,
            metadata: document.metadata
        )
    }
}

private extension ConnectorDocument {
    func matchesCacheEntry(for incoming: ConnectorDocument) -> Bool {
        contentHash == incoming.contentHash
            && modifiedAt == incoming.modifiedAt
            && metadata == incoming.metadata
    }
}
