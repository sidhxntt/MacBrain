import Foundation
import os

actor LocalSourceCoordinator {
    private let logger = Logger(subsystem: "com.macbrain.app", category: "connectors")
    private let repository: LocalSourceRepository
    private let connectors: [SourceConnectorKind: any SourceConnector]
    private let indexingJobs: IndexingJobCoordinator?
    private let syncTimeout: Duration
    private var activeSyncIDs = Set<UUID>()

    init(
        repository: LocalSourceRepository,
        indexingJobs: IndexingJobCoordinator? = nil,
        syncTimeout: Duration = .seconds(120),
        connectors: [any SourceConnector] = [
            AppleNotesConnector(),
            AppleMailLocalStoreConnector(),
            CalendarConnector(),
            RemindersConnector(),
            ContactsConnector(),
            BrowserProfileConnector(),
            MessagesConnector(),
            PhotosMetadataConnector(),
            BooksConnector(),
            FolderConnector(),
            GitRepositoryConnector()
        ]
    ) {
        self.repository = repository
        self.indexingJobs = indexingJobs
        self.syncTimeout = syncTimeout
        self.connectors = Dictionary(uniqueKeysWithValues: connectors.map { ($0.kind, $0) })
    }

    func records() async -> [ConnectorRecord] {
        await repository.allRecords()
    }

    func recoverInterruptedSyncs() async {
        let recordsToRecover = await repository.allRecords().filter { record in
            record.status == .syncing || isLegacyAutomationAuthorizationFailure(record)
        }
        for var record in recordsToRecover {
            if record.status == .syncing {
                record.status = .ready
                record.syncProgress = nil
                // Keep the already-cached snapshot available after a relaunch
                // instead of immediately restarting a large interrupted sync.
                // Normal five-minute refresh logic will reconcile it safely.
                if record.lastSuccessfulSync == nil, record.documentCount > 0 {
                    record.lastSuccessfulSync = .now
                }
            } else {
                record.status = .needsAuthorization
                record.lastError = "MacBrain needs Automation permission to read this source. Open System Settings and allow access, then reauthorize."
            }
            try? await repository.save(record)
        }
    }

    private func isLegacyAutomationAuthorizationFailure(_ record: ConnectorRecord) -> Bool {
        record.kind == .appleMail
            && record.status == .failed
            && (
                record.lastError == "macOS Automation request failed."
                    || record.lastError?.localizedCaseInsensitiveContains("AppleEvent timed out") == true
            )
    }

    func processQueuedIndexing(using provider: any InferenceProvider, embeddingModel: String) async {
        await indexingJobs?.processPending(using: provider, embeddingModel: embeddingModel)
    }

    func create(kind: SourceConnectorKind, displayName: String, configuration: SourceConnectorConfiguration) async throws -> ConnectorRecord {
        if !kind.supportsMultipleConnections,
           let existing = await repository.allRecords().first(where: { $0.kind == kind }) {
            return existing
        }
        let record = ConnectorRecord(kind: kind, displayName: displayName, configuration: configuration)
        try await repository.save(record)
        return record
    }

    func sync(id: UUID) async throws -> ConnectorRecord {
        guard var record = await repository.record(id: id) else {
            throw ConnectorError.sourceUnavailable("This source no longer exists.")
        }
        guard record.status != .paused else { return record }
        guard let connector = connectors[record.kind] else {
            throw ConnectorError.failed("This connector is unavailable.")
        }
        guard activeSyncIDs.insert(id).inserted else { return record }
        defer { activeSyncIDs.remove(id) }

        record.status = .syncing
        record.lastError = nil
        try await repository.save(record)
        logger.info("Connector sync started: \(record.kind.rawValue, privacy: .public)")

        do {
            if let batchedConnector = connector as? any BatchedSourceConnector {
                return try await syncBatches(using: batchedConnector, record: record)
            }

            if let fileBackedConnector = connector as? any FileBackedSourceConnector {
                // File-backed connectors establish security-scoped access as part
                // of scanning. Their async protocol boundary yields this actor while
                // preserving that access in the originating task context.
                let worker = fileBackedConnector
                let syncRecord = record
                let result = try await Self.withTimeout(syncTimeout) {
                    try await Self.scanInWorker(worker, record: syncRecord)
                }
                if let latest = await repository.record(id: id), latest.status == .paused {
                    return latest
                }
                let documentCount = try await repository.reconcileDocuments(
                    for: id,
                    changedDocuments: result.changedDocuments,
                    presentExternalIDs: result.presentExternalIDs
                )
                let changedChunkIDs = await repository.indexedChunkIDs(
                    for: id,
                    externalIDs: Set(result.changedDocuments.map(\.externalID))
                )
                await indexingJobs?.enqueue(sourceID: id, changedChunkIDs: changedChunkIDs)
                record.configuration.fileFingerprints = result.fingerprints
                record.status = .ready
                record.documentCount = documentCount
                record.lastSuccessfulSync = .now
                record.syncProgress = nil
                try await repository.save(record)
                logger.info("Connector incremental sync saved: \(record.kind.rawValue, privacy: .public), count \(documentCount, privacy: .public)")
                return record
            }

            // Apple framework and local-library connectors may enumerate thousands
            // of records synchronously. Persist their result on this actor, but do
            // the scan itself on an independent utility task.
            let worker = connector
            let syncRecord = record
            let documents = try await Self.withTimeout(syncTimeout) {
                try await Self.syncInWorker(worker, record: syncRecord)
            }
            if let latest = await repository.record(id: id), latest.status == .paused {
                return latest
            }
            let changedExternalIDs = await repository.changedExternalIDs(for: id, incoming: documents)
            let documentCount = try await repository.replaceDocuments(for: id, with: documents)
            let changedChunkIDs = await repository.indexedChunkIDs(for: id, externalIDs: changedExternalIDs)
            await indexingJobs?.enqueue(sourceID: id, changedChunkIDs: changedChunkIDs)
            record.status = .ready
            record.documentCount = documentCount
            record.lastSuccessfulSync = .now
            record.syncProgress = nil
            try await repository.save(record)
            logger.info("Connector sync saved: \(record.kind.rawValue, privacy: .public), count \(documentCount, privacy: .public)")
            return record
        } catch is CancellationError {
            record.status = .ready
            record.syncProgress = nil
            try? await repository.save(record)
            throw CancellationError()
        } catch let error as ConnectorError {
            record.status = error.isAuthorizationFailure ? .needsAuthorization : .failed
            record.lastError = error.localizedDescription
            try? await repository.save(record)
            logger.notice("Connector authorization or source failure: \(record.kind.rawValue, privacy: .public)")
            throw error
        } catch {
            let details = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let reflected = String(reflecting: error).trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            if details.isEmpty || details == "The operation couldn’t be completed." {
                message = reflected.isEmpty ? "The source could not be synced." : reflected
            } else {
                message = details
            }
            record.status = .failed
            record.lastError = message
            record.syncProgress = nil
            try? await repository.save(record)
            logger.error("Connector sync failed: \(record.kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            throw ConnectorError.failed(message)
        }
    }

    private func syncBatches(
        using connector: any BatchedSourceConnector,
        record initialRecord: ConnectorRecord
    ) async throws -> ConnectorRecord {
        var record = initialRecord
        var changedExternalIDs = Set<String>()

        while true {
            try Task.checkCancellation()
            let worker = connector
            let batchRecord = record
            let batch = try await Self.withTimeout(syncTimeout) {
                try await Self.batchInWorker(worker, record: batchRecord)
            }
            if let latest = await repository.record(id: record.id), latest.status == .paused {
                return latest
            }
            let batchChangedExternalIDs = await repository.changedExternalIDs(for: record.id, incoming: batch.documents)
            changedExternalIDs.formUnion(batchChangedExternalIDs)
            let documentCount = try await repository.mergeDocuments(
                for: record.id,
                with: batch.documents,
                updateSearchIndex: batch.nextOffset == nil
            )
            record.documentCount = documentCount
            record.configuration.syncOffset = batch.nextOffset
            record.configuration.initialSyncCompleted = batch.initialSyncCompleted
            // Photos uses the same compact syncing treatment as the other
            // source cards; its internal batches remain unchanged.
            record.syncProgress = record.kind == .photos ? nil : batch.progressDescription
            record.status = .syncing
            try await repository.save(record)

            guard batch.nextOffset != nil else { break }
            // Let the app and other connector tasks make progress between batches.
            try await Task.sleep(for: .milliseconds(75))
        }

        record.status = .ready
        record.lastSuccessfulSync = .now
        record.syncProgress = nil
        record.configuration.syncOffset = nil
        try await repository.save(record)
        let changedChunkIDs = await repository.indexedChunkIDs(for: record.id, externalIDs: changedExternalIDs)
        await indexingJobs?.enqueue(sourceID: record.id, changedChunkIDs: changedChunkIDs)
        logger.info("Connector batch sync saved: \(record.kind.rawValue, privacy: .public), count \(record.documentCount, privacy: .public)")
        return record
    }

    func pause(id: UUID) async throws {
        guard var record = await repository.record(id: id) else { return }
        record.status = .paused
        try await repository.save(record)
    }

    func resume(id: UUID) async throws {
        guard var record = await repository.record(id: id) else { return }
        record.status = .ready
        record.lastError = nil
        try await repository.save(record)
    }

    func remove(id: UUID) async throws {
        await indexingJobs?.cancel(sourceID: id)
        try await repository.remove(id: id)
    }

    nonisolated private static func syncInWorker(
        _ connector: any SourceConnector,
        record: ConnectorRecord
    ) async throws -> [ConnectorDocument] {
        try await Task.detached(priority: .utility) {
            try await connector.sync(record: record)
        }.value
    }

    nonisolated private static func batchInWorker(
        _ connector: any BatchedSourceConnector,
        record: ConnectorRecord
    ) async throws -> ConnectorSyncBatch {
        try await Task.detached(priority: .utility) {
            try await connector.syncBatch(record: record)
        }.value
    }

    nonisolated private static func scanInWorker(
        _ connector: any FileBackedSourceConnector,
        record: ConnectorRecord
    ) async throws -> FileBackedSyncResult {
        try await Task.detached(priority: .utility) {
            try await connector.scan(record: record)
        }.value
    }

    nonisolated private static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let result = SyncTimeoutRace<T>()
        let work = Task {
            do {
                await result.resolve(.success(try await operation()))
            } catch {
                await result.resolve(.failure(error))
            }
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
                work.cancel()
                await result.resolve(.failure(ConnectorError.failed("The source sync timed out after 2 minutes.")))
            } catch is CancellationError {
                return
            } catch {
                await result.resolve(.failure(error))
            }
        }
        let completed = await result.wait()
        watchdog.cancel()
        return try completed.get()
    }
}

private actor SyncTimeoutRace<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Result<Value, Error>, Never>?

    func wait() async -> Result<Value, Error> {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            if let result {
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private extension ConnectorError {
    var isAuthorizationFailure: Bool {
        if case .permissionDenied = self { return true }
        return false
    }
}
