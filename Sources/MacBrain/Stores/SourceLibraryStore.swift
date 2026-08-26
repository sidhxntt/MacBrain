import Combine
import Foundation

@MainActor
final class SourceLibraryStore: ObservableObject {
    private static let automaticRefreshInterval: Duration = .seconds(300)
    @Published private(set) var records: [ConnectorRecord] = []
    @Published private(set) var syncActivity: [SourceSyncActivity] = []
    @Published private(set) var nextAutomaticRefresh: Date?
    @Published var alertMessage: String?
    @Published private var syncingRecordIDs = Set<UUID>()
    @Published private var syncingKinds = Set<SourceConnectorKind>()
    private var automaticRefreshTask: Task<Void, Never>?
    private var indexingProvider: (any InferenceProvider)?
    private var selectedEmbeddingModel: (() -> String)?

    let repository: LocalSourceRepository
    private let coordinator: LocalSourceCoordinator
    private let browserProfileCatalog: BrowserProfileCatalog

    init(
        repository: LocalSourceRepository = LocalSourceRepository(),
        coordinator: LocalSourceCoordinator? = nil,
        browserProfileCatalog: BrowserProfileCatalog = BrowserProfileCatalog(),
        database: MacBrainDatabase? = nil
    ) {
        self.repository = repository
        let jobs = database ?? (try? MacBrainDatabase())
        self.coordinator = coordinator ?? LocalSourceCoordinator(
            repository: repository,
            indexingJobs: jobs.map(IndexingJobCoordinator.init)
        )
        self.browserProfileCatalog = browserProfileCatalog
    }

    deinit {
        automaticRefreshTask?.cancel()
    }

    func reload() async {
        records = await coordinator.records()
    }

    func processQueuedIndexing(using provider: any InferenceProvider, embeddingModel: String) async {
        await coordinator.processQueuedIndexing(using: provider, embeddingModel: embeddingModel)
    }

    func configureAutomaticIndexing(
        using provider: any InferenceProvider,
        selectedEmbeddingModel: @escaping () -> String
    ) {
        indexingProvider = provider
        self.selectedEmbeddingModel = selectedEmbeddingModel
    }

    func startAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        nextAutomaticRefresh = .now.addingTimeInterval(300)
        automaticRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.recoverInterruptedSyncs()
            await self.reload()
            await self.retryAuthorizationNeededSources()

            while !Task.isCancelled {
                self.nextAutomaticRefresh = .now.addingTimeInterval(300)
                do {
                    try await Task.sleep(for: Self.automaticRefreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.refreshConnectedSourcesIfDue()
            }
        }
    }

    func stopAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        nextAutomaticRefresh = nil
    }

    func refreshConnectedSourcesNow() async {
        await reload()
        let candidates = records.filter {
            ($0.status == .ready || $0.status == .failed) && !syncingRecordIDs.contains($0.id)
        }
        await refresh(candidates)
    }

    func refreshConnectedSourcesIfDue(referenceDate: Date = .now) async {
        await reload()
        let refreshInterval = Self.automaticRefreshInterval.components.seconds
        let candidates = records.filter { record in
            guard (record.status == .ready || record.status == .failed), !syncingRecordIDs.contains(record.id) else { return false }
            guard let lastSuccessfulSync = record.lastSuccessfulSync else { return true }
            return referenceDate.timeIntervalSince(lastSuccessfulSync) >= Double(refreshInterval)
        }
        await refresh(candidates)
    }

    /// A source can retain the permission-needed status after the user changes a
    /// macOS privacy setting. Retry those explicitly connected sources once at
    /// startup so the new grant takes effect without requiring a manual menu action.
    func retryAuthorizationNeededSources() async {
        await reload()
        let candidates = records.filter { $0.status == .needsAuthorization && !syncingRecordIDs.contains($0.id) }
        await refresh(candidates)
    }

    func isSyncing(kind: SourceConnectorKind) -> Bool {
        syncingKinds.contains(kind)
    }

    func isSyncing(_ record: ConnectorRecord) -> Bool {
        syncingRecordIDs.contains(record.id)
    }

    func addAndSync(kind: SourceConnectorKind, displayName: String, configuration: SourceConnectorConfiguration) {
        guard !syncingKinds.contains(kind) else { return }
        syncingKinds.insert(kind)
        alertMessage = nil

        Task {
            var recordID: UUID?
            do {
                let record = try await self.coordinator.create(
                    kind: kind,
                    displayName: displayName,
                    configuration: configuration
                )
                recordID = record.id
                self.syncingRecordIDs.insert(record.id)
                // Show confirmed sources immediately, including their syncing state.
                await self.reload()
                if let index = self.records.firstIndex(where: { $0.id == record.id }) {
                    self.records[index].status = .syncing
                    self.records[index].lastError = nil
                }
                let refreshTask = Task { [weak self] in
                    await self?.refreshWhileSyncing(recordID: record.id)
                }
                defer { refreshTask.cancel() }
                _ = try await self.coordinator.sync(id: record.id)
            } catch {
                self.alertMessage = error.localizedDescription
                if let recordID, let record = await self.record(id: recordID) {
                    self.appendActivity(for: record, state: .needsAttention, detail: self.activityDetail(for: error))
                }
            }
            if let recordID {
                self.syncingRecordIDs.remove(recordID)
            }
            self.syncingKinds.remove(kind)
            await self.reload()
        }
    }

    /// Browser Profiles is one explicit consent action. It discovers only known local
    /// profile roots, then keeps every resulting source in the normal refresh loop.
    func connectInstalledBrowserProfiles() {
        let kind = SourceConnectorKind.browserProfile
        guard !syncingKinds.contains(kind) else { return }
        syncingKinds.insert(kind)
        alertMessage = nil

        let profiles: [DetectedBrowserProfile]
        do {
            profiles = try browserProfileCatalog.detectedProfiles().filter { $0.browserKind != nil }
        } catch {
            syncingKinds.remove(kind)
            alertMessage = "MacBrain could not inspect local browser profiles."
            return
        }

        guard !profiles.isEmpty else {
            syncingKinds.remove(kind)
            alertMessage = "No supported browser profiles were found on this Mac."
            return
        }

        Task {
            await self.reload()
            var recordsToSync: [ConnectorRecord] = []
            for profile in profiles {
                guard let browser = profile.browserKind else { continue }
                let existing = self.records.first {
                    $0.kind == .browserProfile
                        && $0.configuration.browserKind == browser
                        && $0.configuration.localPath == profile.profileURL.path
                }

                if let existing {
                    recordsToSync.append(existing)
                    continue
                }

                do {
                    let record = try await self.coordinator.create(
                        kind: .browserProfile,
                        displayName: "\(profile.browserDisplayName) · \(profile.profileDisplayName)",
                        configuration: SourceConnectorConfiguration(
                            localPath: profile.profileURL.path,
                            browserKind: browser,
                            browserDisplayName: profile.browserDisplayName,
                            browserProfileName: profile.profileDisplayName
                        )
                    )
                    await self.reload()
                    recordsToSync.append(record)
                } catch {
                    self.alertMessage = error.localizedDescription
                }
            }
            await self.syncBrowserProfiles(recordsToSync)
            self.syncingKinds.remove(kind)
            await self.reload()
        }
    }

    func sync(_ record: ConnectorRecord) {
        perform(for: record.id) { _ = try await self.coordinator.sync(id: record.id) }
    }

    func pause(_ record: ConnectorRecord) {
        Task {
            do {
                try await self.coordinator.pause(id: record.id)
            } catch {
                self.alertMessage = error.localizedDescription
            }
            await self.reload()
        }
    }

    func resume(_ record: ConnectorRecord) {
        perform(for: record.id) {
            try await self.coordinator.resume(id: record.id)
            _ = try await self.coordinator.sync(id: record.id)
        }
    }

    func delete(_ record: ConnectorRecord) {
        // Deletion must never be blocked by an in-flight sync. The coordinator and
        // repository prevent that sync from restoring this record after removal.
        syncingRecordIDs.remove(record.id)
        alertMessage = nil
        records.removeAll { $0.id == record.id }

        Task {
            do {
                try await self.coordinator.remove(id: record.id)
            } catch {
                self.alertMessage = error.localizedDescription
            }
            await self.reload()
        }
    }

    private func perform(for recordID: UUID, _ operation: @escaping @Sendable () async throws -> Void) {
        guard !syncingRecordIDs.contains(recordID) else { return }
        syncingRecordIDs.insert(recordID)
        alertMessage = nil
        Task {
            let refreshTask = Task { [weak self] in
                await self?.refreshWhileSyncing(recordID: recordID)
            }
            defer { refreshTask.cancel() }
            do {
                try await operation()
            } catch {
                self.alertMessage = error.localizedDescription
                if let record = await self.record(id: recordID) {
                    self.appendActivity(for: record, state: .needsAttention, detail: self.activityDetail(for: error))
                }
            }
            self.syncingRecordIDs.remove(recordID)
            await self.reload()
        }
    }

    private func refreshWhileSyncing(recordID: UUID) async {
        while syncingRecordIDs.contains(recordID) && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func syncBrowserProfile(_ record: ConnectorRecord) async {
        guard !syncingRecordIDs.contains(record.id) else { return }
        syncingRecordIDs.insert(record.id)
        let refreshTask = Task { [weak self] in
            await self?.refreshWhileSyncing(recordID: record.id)
        }
        defer {
            refreshTask.cancel()
            syncingRecordIDs.remove(record.id)
        }

        do {
            let refreshed = try await coordinator.sync(id: record.id)
            await processIndexingIfConfigured()
            let count = "\(refreshed.documentCount) \(refreshed.documentCount == 1 ? "item" : "items")"
            appendActivity(for: refreshed, state: .completed, detail: "Initial browser sync complete · \(count)")
        } catch {
            alertMessage = error.localizedDescription
            if let current = await self.record(id: record.id) {
                appendActivity(for: current, state: .needsAttention, detail: activityDetail(for: error))
            }
        }
    }

    private func syncBrowserProfiles(_ records: [ConnectorRecord]) async {
        await withTaskGroup(of: Void.self) { group in
            for record in records {
                group.addTask { [weak self, record] in
                    guard let self else { return }
                    await self.syncBrowserProfile(record)
                }
            }
            await group.waitForAll()
        }
    }

    private func refreshAutomatically(_ record: ConnectorRecord) async {
        guard !syncingRecordIDs.contains(record.id) else { return }
        syncingRecordIDs.insert(record.id)
        appendActivity(for: record, state: .syncing, detail: "Background refresh started")
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index].status = .syncing
            records[index].lastError = nil
        }
        defer {
            syncingRecordIDs.remove(record.id)
        }

        do {
            let refreshed = try await coordinator.sync(id: record.id)
            let count = "\(refreshed.documentCount) \(refreshed.documentCount == 1 ? "item" : "items")"
            appendActivity(for: refreshed, state: .completed, detail: "Background refresh complete · \(count)")
        } catch is CancellationError {
            return
        } catch {
            appendActivity(for: record, state: .needsAttention, detail: activityDetail(for: error))
        }
        await reload()
    }

    private func refresh(_ candidates: [ConnectorRecord]) async {
        guard !candidates.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for record in candidates where !Task.isCancelled {
                group.addTask { [weak self, record] in
                    guard let self else { return }
                    await self.refreshAutomatically(record)
                }
            }
            await group.waitForAll()
        }
        // Connector scans remain parallel, while the durable indexing queue is
        // consumed once after all source commits have settled.
        await processIndexingIfConfigured()
    }

    private func processIndexingIfConfigured() async {
        guard let indexingProvider, let selectedEmbeddingModel else { return }
        await coordinator.processQueuedIndexing(
            using: indexingProvider,
            embeddingModel: selectedEmbeddingModel()
        )
    }

    private func record(id: UUID) async -> ConnectorRecord? {
        await coordinator.records().first { $0.id == id }
    }

    private func activityDetail(for error: Error) -> String {
        guard let error = error as? ConnectorError else {
            return "Refresh needs attention"
        }

        if case .permissionDenied = error {
            return "Authorization required"
        }
        return "Refresh needs attention"
    }

    private func appendActivity(
        for record: ConnectorRecord,
        state: SourceSyncActivityState,
        detail: String
    ) {
        syncActivity.insert(
            SourceSyncActivity(
                sourceID: record.id,
                sourceName: record.displayName,
                state: state,
                detail: detail
            ),
            at: 0
        )
        if syncActivity.count > 12 {
            syncActivity.removeLast(syncActivity.count - 12)
        }
    }
}
