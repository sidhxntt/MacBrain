import Foundation
import Testing
@testable import MacBrain

struct ConnectorRefreshSchedulerTests {
    @Test
    func refreshesOnlyDueSourcesWithBoundedConcurrencyAndFailureIsolation() async throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let dueRecords = (0..<4).map { index in
            ConnectorRecord(
                kind: .folder,
                displayName: "Due \(index)",
                configuration: .init(),
                status: .ready,
                lastSuccessfulSync: now.addingTimeInterval(index == 0 ? -300 : -600)
            )
        }
        let recent = ConnectorRecord(
            kind: .folder,
            displayName: "Recent",
            configuration: .init(),
            status: .ready,
            lastSuccessfulSync: now.addingTimeInterval(-299)
        )
        let paused = ConnectorRecord(
            kind: .folder,
            displayName: "Paused",
            configuration: .init(),
            status: .paused,
            lastSuccessfulSync: now.addingTimeInterval(-900)
        )
        let probe = SchedulerRefreshProbe(
            candidates: dueRecords + [dueRecords[0], recent, paused],
            failingSourceIDs: [dueRecords[1].id]
        )
        let events = SchedulerEventRecorder()
        let scheduler = ConnectorRefreshScheduler(
            interval: .seconds(300),
            maximumConcurrentRefreshes: 3,
            clock: ManualConnectorRefreshClock(now: now),
            loadCandidates: { await probe.loadCandidates() },
            refresh: { try await probe.refresh($0) },
            onEvent: { await events.record($0) }
        )

        let refreshTask = Task {
            await scheduler.runDueRefresh(referenceDate: now)
        }
        await probe.waitUntilStarted(count: 3)
        #expect(await probe.maximumConcurrency() == 3)
        await probe.releaseAll()
        await refreshTask.value

        #expect(await probe.startedSourceIDs() == Set(dueRecords.map(\.id)))
        #expect(await probe.refreshCount(for: dueRecords[0].id) == 1)
        #expect(await probe.refreshCount(for: recent.id) == 0)
        #expect(await probe.refreshCount(for: paused.id) == 0)
        #expect(await events.failedSourceIDs() == [dueRecords[1].id])
        #expect(await events.succeededSourceIDs().count == 3)
    }

    @Test
    func concurrentDueRunsCoalesceTheSameSource() async throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(),
            status: .ready,
            lastSuccessfulSync: now.addingTimeInterval(-300)
        )
        let probe = SchedulerRefreshProbe(candidates: [record])
        let scheduler = ConnectorRefreshScheduler(
            clock: ManualConnectorRefreshClock(now: now),
            loadCandidates: { await probe.loadCandidates() },
            refresh: { try await probe.refresh($0) }
        )

        let first = Task { await scheduler.runDueRefresh(referenceDate: now) }
        await probe.waitUntilStarted(count: 1)
        let second = Task { await scheduler.runDueRefresh(referenceDate: now) }
        await second.value
        await probe.releaseAll()
        await first.value

        #expect(await probe.refreshCount(for: record.id) == 1)
    }

    @Test
    func loopWaitsExactlyFiveMinutesAndStopsCleanly() async throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let record = ConnectorRecord(
            kind: .calendar,
            displayName: "Apple Calendar",
            configuration: .init(),
            status: .ready
        )
        let clock = ManualConnectorRefreshClock(now: now)
        let probe = SchedulerRefreshProbe(candidates: [record], startsReleased: true)
        let scheduler = ConnectorRefreshScheduler(
            interval: .seconds(300),
            maximumConcurrentRefreshes: 2,
            clock: clock,
            loadCandidates: { await probe.loadCandidates() },
            refresh: { try await probe.refresh($0) }
        )

        await scheduler.start()
        await clock.waitForSleepRegistrations(1)
        await clock.advance(by: .seconds(299))
        #expect(await probe.refreshCount(for: record.id) == 0)

        await clock.advance(by: .seconds(1))
        await probe.waitUntilStarted(count: 1)
        await clock.waitForSleepRegistrations(2)
        await scheduler.stop()

        #expect(await probe.refreshCount(for: record.id) == 1)
        #expect(await clock.pendingSleepCount() == 0)
        #expect(await scheduler.isRunning == false)
    }
}

private actor SchedulerRefreshProbe {
    private let candidates: [ConnectorRecord]
    private let failingSourceIDs: Set<UUID>
    private var released: Bool
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var counts: [UUID: Int] = [:]
    private var startedIDs = Set<UUID>()
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        candidates: [ConnectorRecord],
        failingSourceIDs: Set<UUID> = [],
        startsReleased: Bool = false
    ) {
        self.candidates = candidates
        self.failingSourceIDs = failingSourceIDs
        released = startsReleased
    }

    func loadCandidates() -> [ConnectorRecord] { candidates }

    func refresh(_ record: ConnectorRecord) async throws -> ConnectorRecord {
        counts[record.id, default: 0] += 1
        startedIDs.insert(record.id)
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        resumeSatisfiedStartWaiters()
        if !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        activeCount -= 1
        if failingSourceIDs.contains(record.id) {
            throw ConnectorError.failed("Controlled scheduler failure")
        }
        return record
    }

    func waitUntilStarted(count: Int) async {
        if counts.values.reduce(0, +) >= count { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func releaseAll() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func maximumConcurrency() -> Int { maximumActiveCount }
    func startedSourceIDs() -> Set<UUID> { startedIDs }
    func refreshCount(for sourceID: UUID) -> Int { counts[sourceID, default: 0] }

    private func resumeSatisfiedStartWaiters() {
        let total = counts.values.reduce(0, +)
        let satisfied = startWaiters.filter { $0.0 <= total }
        startWaiters.removeAll { $0.0 <= total }
        for (_, waiter) in satisfied { waiter.resume() }
    }
}

private actor SchedulerEventRecorder {
    private var events: [ConnectorRefreshEvent] = []

    func record(_ event: ConnectorRefreshEvent) { events.append(event) }

    func failedSourceIDs() -> [UUID] {
        events.compactMap { event in
            guard case .failed(let sourceID, _) = event else { return nil }
            return sourceID
        }
    }

    func succeededSourceIDs() -> [UUID] {
        events.compactMap { event in
            guard case .succeeded(let sourceID, _) = event else { return nil }
            return sourceID
        }
    }
}

private actor ManualConnectorRefreshClock: ConnectorRefreshClock {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, Error>
    }

    private var currentDate: Date
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelledBeforeRegistration = Set<UUID>()
    private var sleepRegistrations = 0
    private var registrationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(now: Date) {
        currentDate = now
    }

    func now() -> Date { currentDate }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled || cancelledBeforeRegistration.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepers[id] = Sleeper(
                    deadline: currentDate.addingTimeInterval(duration.timeInterval),
                    continuation: continuation
                )
                sleepRegistrations += 1
                resumeSatisfiedRegistrationWaiters()
            }
        } onCancel: {
            Task { await self.cancelSleep(id: id) }
        }
    }

    func advance(by duration: Duration) {
        currentDate = currentDate.addingTimeInterval(duration.timeInterval)
        let due = sleepers.filter { $0.value.deadline <= currentDate }
        for (id, sleeper) in due {
            sleepers[id] = nil
            sleeper.continuation.resume()
        }
    }

    func waitForSleepRegistrations(_ count: Int) async {
        if sleepRegistrations >= count { return }
        await withCheckedContinuation { continuation in
            registrationWaiters.append((count, continuation))
        }
    }

    func pendingSleepCount() -> Int { sleepers.count }

    private func cancelSleep(id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else {
            cancelledBeforeRegistration.insert(id)
            return
        }
        sleeper.continuation.resume(throwing: CancellationError())
    }

    private func resumeSatisfiedRegistrationWaiters() {
        let satisfied = registrationWaiters.filter { $0.0 <= sleepRegistrations }
        registrationWaiters.removeAll { $0.0 <= sleepRegistrations }
        for (_, waiter) in satisfied { waiter.resume() }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
