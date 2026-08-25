import Foundation
import os

actor LocalSourceCoordinator {
    private let logger = Logger(subsystem: "com.macbrain.app", category: "connectors")
    private let repository: LocalSourceRepository
    private let connectors: [SourceConnectorKind: any SourceConnector]

    init(
        repository: LocalSourceRepository,
        connectors: [any SourceConnector] = [
            AppleNotesConnector(),
            AppleMailConnector(),
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
        self.connectors = Dictionary(uniqueKeysWithValues: connectors.map { ($0.kind, $0) })
    }

    func records() async -> [ConnectorRecord] {
        await repository.allRecords()
    }

    func recoverInterruptedSyncs() async {
        let interrupted = await repository.allRecords().filter { $0.status == .syncing }
        for var record in interrupted {
            record.status = .ready
            record.syncProgress = nil
            try? await repository.save(record)
        }
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

        record.status = .syncing
        record.lastError = nil
        try await repository.save(record)
        logger.info("Connector sync started: \(record.kind.rawValue, privacy: .public)")

        do {
            if let batchedConnector = connector as? any BatchedSourceConnector {
                return try await syncBatches(using: batchedConnector, record: record)
            }

            let documents = try await connector.sync(record: record)
            if let latest = await repository.record(id: id), latest.status == .paused {
                return latest
            }
            let documentCount = try await repository.replaceDocuments(for: id, with: documents)
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
            record.status = .failed
            record.lastError = "The source could not be synced."
            try? await repository.save(record)
            logger.error("Connector sync failed: \(record.kind.rawValue, privacy: .public)")
            throw ConnectorError.failed("The source could not be synced.")
        }
    }

    private func syncBatches(
        using connector: any BatchedSourceConnector,
        record initialRecord: ConnectorRecord
    ) async throws -> ConnectorRecord {
        var record = initialRecord

        while true {
            try Task.checkCancellation()
            let batch = try await connector.syncBatch(record: record)
            if let latest = await repository.record(id: record.id), latest.status == .paused {
                return latest
            }
            let documentCount = try await repository.mergeDocuments(for: record.id, with: batch.documents)

            record.documentCount = documentCount
            record.configuration.syncOffset = batch.nextOffset
            record.configuration.initialSyncCompleted = batch.initialSyncCompleted
            record.syncProgress = batch.progressDescription
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
        try await repository.remove(id: id)
    }
}

private extension ConnectorError {
    var isAuthorizationFailure: Bool {
        if case .permissionDenied = self { return true }
        return false
    }
}
