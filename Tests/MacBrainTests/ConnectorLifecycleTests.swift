import Foundation
import Testing
@testable import MacBrain

struct ConnectorLifecycleTests {
    @Test
    func connectBecomesReadyOnlyAfterSearchableCommit() async throws {
        let fixture = try LifecycleFixture()
        let connector = GatedLifecycleConnector(kind: .appleNotes)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [connector]
        )
        let record = try await coordinator.create(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )
        #expect(record.status == .syncing)

        let syncTask = Task { try await coordinator.sync(id: record.id) }
        await connector.waitUntilStarted()
        #expect(await fixture.repository.record(id: record.id)?.status == .syncing)
        #expect(await fixture.repository.indexHealth(for: record.id) == nil)
        #expect(try await fixture.database.searchChunks(matching: "ORBIT-READY").isEmpty)

        await connector.finish(with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "note-1",
                title: "Verified note",
                text: "ORBIT-READY is searchable",
                sourceLabel: "Apple Notes"
            )
        ])
        let completed = try await syncTask.value
        let health = try #require(await fixture.repository.indexHealth(for: record.id))

        #expect(completed.status == .ready)
        #expect(completed.documentCount == 1)
        #expect(health.isSearchable)
        #expect(try await fixture.database.searchChunks(matching: "ORBIT-READY").count == 1)
    }

    @Test
    func zeroDocumentInitialSyncCreatesVerifiedEmptyReadyState() async throws {
        let fixture = try LifecycleFixture()
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [FixedLifecycleConnector(kind: .books, documents: [])]
        )
        let record = try await coordinator.create(
            kind: .books,
            displayName: "Apple Books",
            configuration: .init()
        )

        let completed = try await coordinator.sync(id: record.id)
        let health = try #require(await fixture.repository.indexHealth(for: record.id))

        #expect(completed.status == .ready)
        #expect(health.isSearchable)
        #expect(health.isEmpty)
    }

    @Test
    func interruptedUnverifiedInitialSyncRestartsInsteadOfBecomingOptimisticallyReady() async throws {
        let fixture = try LifecycleFixture()
        let probe = CountingLifecycleConnector(kind: .calendar)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [probe]
        )
        let record = try await coordinator.create(
            kind: .calendar,
            displayName: "Apple Calendar",
            configuration: .init()
        )

        await coordinator.recoverInterruptedSyncs()

        #expect(await probe.syncCount() == 1)
        #expect(await fixture.repository.record(id: record.id)?.status == .ready)
        #expect(await fixture.repository.indexHealth(for: record.id)?.isSearchable == true)
    }

    @Test
    func legacyReadyRecordWithoutVerifiedGenerationResyncsImmediatelyOnRecovery() async throws {
        let fixture = try LifecycleFixture()
        let probe = CountingLifecycleConnector(kind: .books)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [probe]
        )
        let legacyReadyRecord = ConnectorRecord(
            kind: .books,
            displayName: "Apple Books",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        try await fixture.repository.save(legacyReadyRecord)
        #expect(await fixture.repository.verifiedIndexHealth(for: legacyReadyRecord.id) == nil)

        await coordinator.recoverInterruptedSyncs()

        #expect(await probe.syncCount() == 1)
        #expect(await fixture.repository.record(id: legacyReadyRecord.id)?.status == .ready)
        #expect(await fixture.repository.verifiedIndexHealth(for: legacyReadyRecord.id)?.isSearchable == true)
    }

    @Test
    func stalledRecoveryDoesNotPreventAnotherUnverifiedConnectorFromStarting() async throws {
        let fixture = try LifecycleFixture()
        let stalled = GatedLifecycleConnector(kind: .folder)
        let fast = CountingLifecycleConnector(kind: .books)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [stalled, fast]
        )
        let records = [
            ConnectorRecord(
                kind: .folder,
                displayName: "A stalled folder",
                configuration: .init(initialSyncCompleted: true),
                status: .ready,
                lastSuccessfulSync: .now
            ),
            ConnectorRecord(
                kind: .books,
                displayName: "B books",
                configuration: .init(initialSyncCompleted: true),
                status: .ready,
                lastSuccessfulSync: .now
            ),
        ]
        for record in records { try await fixture.repository.save(record) }

        let recovery = Task { await coordinator.recoverInterruptedSyncs() }
        await stalled.waitUntilStarted()
        await fast.waitUntilStarted()
        let fastCountBeforeStalledFinished = await fast.syncCount()

        await stalled.finish(with: [])
        await recovery.value

        #expect(fastCountBeforeStalledFinished == 1)
        #expect(await fixture.repository.verifiedIndexHealth(for: records[1].id)?.isSearchable == true)
    }

    @Test
    func interruptedRefreshUsesVerifiedIndexWithoutRequiringSourceChanges() async throws {
        let fixture = try LifecycleFixture()
        let probe = CountingLifecycleConnector(kind: .reminders)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [probe]
        )
        let created = try await coordinator.create(
            kind: .reminders,
            displayName: "Apple Reminders",
            configuration: .init()
        )
        _ = try await coordinator.sync(id: created.id)
        var interrupted = try #require(await fixture.repository.record(id: created.id))
        interrupted.status = .syncing
        try await fixture.repository.save(interrupted)

        await coordinator.recoverInterruptedSyncs()

        #expect(await probe.syncCount() == 1)
        #expect(await fixture.repository.record(id: created.id)?.status == .ready)
        #expect(await fixture.repository.indexHealth(for: created.id)?.isSearchable == true)
    }

    @Test
    func interruptedBatchedRefreshRestartsFromTheFirstPage() async throws {
        let fixture = try LifecycleFixture()
        var ready = ConnectorRecord(
            kind: .messages,
            displayName: "Messages",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try await fixture.repository.commitSourceGeneration(
            record: ready,
            documents: [
                ConnectorDocument(
                    connectorID: ready.id,
                    externalID: "verified-message",
                    title: "Verified message",
                    text: "PREVIOUS-VERIFIED-GENERATION remains searchable",
                    sourceLabel: "Messages"
                )
            ]
        )
        ready = try #require(await fixture.repository.record(id: ready.id))
        ready.status = .syncing
        ready.configuration.syncOffset = 1
        ready.syncProgress = "Indexed batch 1"
        try await fixture.repository.save(ready)

        let probe = RecoveryOffsetProbeBatchedConnector()
        let recoveredCoordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [probe]
        )
        await recoveredCoordinator.recoverInterruptedSyncs()

        #expect(await probe.observedOffsets() == [nil, 1])
        let recovered = try #require(await fixture.repository.record(id: ready.id))
        #expect(recovered.status == .ready)
        #expect(recovered.configuration.syncOffset == nil)
        #expect(recovered.documentCount == 3)
        #expect(try await fixture.database.searchChunks(matching: "RECOVERY-PAGE-ZERO").count == 1)
        #expect(try await fixture.database.searchChunks(matching: "RECOVERY-PAGE-ONE").count == 1)
    }

    @Test
    func failedRefreshRetainsTheLastVerifiedSearchableGeneration() async throws {
        let fixture = try LifecycleFixture()
        let connector = SucceedThenFailLifecycleConnector(kind: .contacts)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [connector]
        )
        let record = try await coordinator.create(
            kind: .contacts,
            displayName: "Apple Contacts",
            configuration: .init()
        )
        _ = try await coordinator.sync(id: record.id)
        let verifiedHealth = try #require(
            await fixture.repository.indexHealth(for: record.id)
        )

        do {
            _ = try await coordinator.sync(id: record.id)
            Issue.record("Expected the controlled refresh to fail")
        } catch {
            #expect(error as? ConnectorError == .failed("Controlled refresh failure"))
        }

        #expect(await fixture.repository.record(id: record.id)?.status == .failed)
        #expect(await fixture.repository.indexHealth(for: record.id) == verifiedHealth)
        #expect(try await fixture.database.searchChunks(matching: "RETAINED-INDEX").count == 1)
    }

    @Test
    func concurrentSyncCallersReceiveTheSameCommittedGeneration() async throws {
        let fixture = try LifecycleFixture()
        let connector = GatedLifecycleConnector(kind: .appleNotes)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [connector]
        )
        let record = try await coordinator.create(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )

        let firstSync = Task { try await coordinator.sync(id: record.id) }
        await connector.waitUntilStarted()
        let secondSync = Task { try await coordinator.sync(id: record.id) }
        for _ in 0..<8 { await Task.yield() }

        await connector.finish(with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "coalesced-note",
                title: "Coalesced note",
                text: "COALESCED-GENERATION is searchable",
                sourceLabel: "Apple Notes"
            )
        ])
        let firstResult = try await firstSync.value
        let secondResult = try await secondSync.value

        #expect(await connector.syncCount() == 1)
        #expect(firstResult.status == .ready)
        #expect(secondResult.status == .ready)
        #expect(secondResult.documentCount == 1)
        #expect(secondResult.lastSuccessfulSync == firstResult.lastSuccessfulSync)
    }

    @Test
    func cancellingInitialSyncCancelsScanningAndPreventsACommit() async throws {
        let fixture = try LifecycleFixture()
        let connector = GatedLifecycleConnector(kind: .appleNotes)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [connector]
        )
        let record = try await coordinator.create(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )
        let syncTask = Task { try await coordinator.sync(id: record.id) }
        await connector.waitUntilStarted()

        syncTask.cancel()
        await connector.finish(with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "must-not-commit",
                title: "Cancelled note",
                text: "CANCELLED-CONTENT must not become searchable",
                sourceLabel: "Apple Notes"
            )
        ])

        await #expect(throws: CancellationError.self) {
            try await syncTask.value
        }
        #expect(await connector.observedCancellation())
        #expect(await fixture.repository.verifiedIndexHealth(for: record.id) == nil)
        #expect(try await fixture.database.searchChunks(matching: "CANCELLED-CONTENT").isEmpty)
    }

    @Test
    func cancellingACoalescedWaiterDoesNotCancelTheSharedSync() async throws {
        let fixture = try LifecycleFixture()
        let connector = GatedLifecycleConnector(kind: .appleNotes)
        let coordinator = LocalSourceCoordinator(
            repository: fixture.repository,
            connectors: [connector]
        )
        let record = try await coordinator.create(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )
        let owner = Task { try await coordinator.sync(id: record.id) }
        await connector.waitUntilStarted()
        let waiter = Task { try await coordinator.sync(id: record.id) }
        waiter.cancel()

        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
        await connector.finish(with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "owner-note",
                title: "Owner note",
                text: "OWNER-SYNC remains active",
                sourceLabel: "Apple Notes"
            )
        ])
        let ownerResult = try await owner.value

        #expect(ownerResult.status == .ready)
        #expect(ownerResult.documentCount == 1)
        #expect(await connector.syncCount() == 1)
    }
}

private struct LifecycleFixture {
    let database: MacBrainDatabase
    let repository: LocalSourceRepository

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-lifecycle-tests-" + UUID().uuidString,
            isDirectory: true
        )
        let database = try MacBrainDatabase(
            url: directory.appendingPathComponent("macbrain.sqlite")
        )
        self.database = database
        repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("local-sources.json"),
            database: database
        )
    }
}

private actor GatedLifecycleConnector: SourceConnector {
    nonisolated let kind: SourceConnectorKind
    private var count = 0
    private var didStart = false
    private var didObserveCancellation = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var result: [ConnectorDocument]?
    private var resultWaiter: CheckedContinuation<[ConnectorDocument], Never>?

    init(kind: SourceConnectorKind) {
        self.kind = kind
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        count += 1
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        let documents: [ConnectorDocument]
        if let result {
            documents = result
        } else {
            documents = await withCheckedContinuation { continuation in
                resultWaiter = continuation
            }
        }
        if Task.isCancelled {
            didObserveCancellation = true
            throw CancellationError()
        }
        return documents
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(with documents: [ConnectorDocument]) {
        result = documents
        resultWaiter?.resume(returning: documents)
        resultWaiter = nil
    }

    func syncCount() -> Int { count }
    func observedCancellation() -> Bool { didObserveCancellation }
}

private struct FixedLifecycleConnector: SourceConnector {
    let kind: SourceConnectorKind
    let documents: [ConnectorDocument]

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        documents
    }
}

private actor CountingLifecycleConnector: SourceConnector {
    nonisolated let kind: SourceConnectorKind
    private var count = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(kind: SourceConnectorKind) {
        self.kind = kind
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        count += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "controlled-\(kind.rawValue)",
                title: "Controlled \(kind.displayName)",
                text: "Verified lifecycle content",
                sourceLabel: kind.displayName
            )
        ]
    }

    func waitUntilStarted() async {
        if count > 0 { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func syncCount() -> Int { count }
}

private actor SucceedThenFailLifecycleConnector: SourceConnector {
    nonisolated let kind: SourceConnectorKind
    private var count = 0

    init(kind: SourceConnectorKind) {
        self.kind = kind
    }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        count += 1
        guard count == 1 else {
            throw ConnectorError.failed("Controlled refresh failure")
        }
        return [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "retained",
                title: "Retained contact",
                text: "RETAINED-INDEX remains searchable",
                sourceLabel: kind.displayName
            )
        ]
    }
}

private actor RecoveryOffsetProbeBatchedConnector: BatchedSourceConnector {
    nonisolated let kind: SourceConnectorKind = .messages
    private var offsets: [Int?] = []

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        try await syncBatch(record: record).documents
    }

    func syncBatch(record: ConnectorRecord) async throws -> ConnectorSyncBatch {
        let offset = record.configuration.syncOffset ?? 0
        offsets.append(record.configuration.syncOffset)
        return ConnectorSyncBatch(
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "recovery-page-\(offset)",
                    title: "Recovery page \(offset)",
                    text: offset == 0 ? "RECOVERY-PAGE-ZERO" : "RECOVERY-PAGE-ONE",
                    sourceLabel: "Messages"
                )
            ],
            nextOffset: offset == 0 ? 1 : nil,
            initialSyncCompleted: true,
            progressDescription: "Indexed recovery batch \(offset + 1)"
        )
    }

    func observedOffsets() -> [Int?] { offsets }
}
