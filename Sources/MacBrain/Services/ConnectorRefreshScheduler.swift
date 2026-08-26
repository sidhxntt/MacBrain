import Foundation

protocol ConnectorRefreshClock: Sendable {
    func sleep(for duration: Duration) async throws
    func now() async -> Date
}

struct ContinuousConnectorRefreshClock: ConnectorRefreshClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    func now() async -> Date { .now }
}

enum ConnectorRefreshEvent: Equatable, Sendable {
    case scheduled(Date)
    case started(UUID)
    case succeeded(UUID, Int)
    case failed(UUID, String)
    case stopped
}

actor ConnectorRefreshScheduler {
    typealias CandidateLoader = @Sendable () async -> [ConnectorRecord]
    typealias RefreshOperation = @Sendable (ConnectorRecord) async throws -> ConnectorRecord
    typealias EventSink = @Sendable (ConnectorRefreshEvent) async -> Void

    private let interval: Duration
    private let maximumConcurrentRefreshes: Int
    private let clock: any ConnectorRefreshClock
    private let loadCandidates: CandidateLoader
    private let refresh: RefreshOperation
    private let onEvent: EventSink
    private var loopTask: Task<Void, Never>?
    private var loopID: UUID?
    private var inFlightSourceIDs = Set<UUID>()
    private(set) var nextRunAt: Date?

    var isRunning: Bool { loopTask != nil }

    init(
        interval: Duration = .seconds(300),
        maximumConcurrentRefreshes: Int = 3,
        clock: any ConnectorRefreshClock = ContinuousConnectorRefreshClock(),
        loadCandidates: @escaping CandidateLoader,
        refresh: @escaping RefreshOperation,
        onEvent: @escaping EventSink = { _ in }
    ) {
        self.interval = interval
        self.maximumConcurrentRefreshes = max(1, maximumConcurrentRefreshes)
        self.clock = clock
        self.loadCandidates = loadCandidates
        self.refresh = refresh
        self.onEvent = onEvent
    }

    func start() {
        guard loopTask == nil else { return }
        let id = UUID()
        loopID = id
        loopTask = Task { [weak self] in
            await self?.runLoop(id: id)
        }
    }

    func stop() async {
        guard let task = loopTask else {
            nextRunAt = nil
            return
        }
        loopID = nil
        loopTask = nil
        nextRunAt = nil
        task.cancel()
        await task.value
        await onEvent(.stopped)
    }

    func runDueRefresh(referenceDate: Date? = nil) async {
        let now: Date
        if let referenceDate {
            now = referenceDate
        } else {
            now = await clock.now()
        }
        let loadedCandidates = await loadCandidates()
        var seenSourceIDs = Set<UUID>()
        let candidates = loadedCandidates.filter { record in
            guard seenSourceIDs.insert(record.id).inserted,
                  isRefreshEligible(record),
                  !inFlightSourceIDs.contains(record.id) else {
                return false
            }
            guard let lastSuccessfulSync = record.lastSuccessfulSync else {
                return true
            }
            return now.timeIntervalSince(lastSuccessfulSync) >= interval.timeInterval
        }
        await runRefresh(candidates)
    }

    func runRefresh(_ candidates: [ConnectorRecord]) async {
        var seenSourceIDs = Set<UUID>()
        let candidates = candidates.filter { record in
            seenSourceIDs.insert(record.id).inserted
                && record.status != .paused
                && !inFlightSourceIDs.contains(record.id)
        }
        guard !candidates.isEmpty else { return }

        let selectedSourceIDs = Set(candidates.map(\.id))
        inFlightSourceIDs.formUnion(selectedSourceIDs)
        defer { inFlightSourceIDs.subtract(selectedSourceIDs) }

        await withTaskGroup(of: RefreshOutcome.self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<maximumConcurrentRefreshes {
                guard let candidate = iterator.next() else { break }
                addRefresh(candidate, to: &group)
            }

            while let outcome = await group.next() {
                switch outcome {
                case .succeeded(let sourceID, let documentCount):
                    await onEvent(.succeeded(sourceID, documentCount))
                case .failed(let sourceID, let message):
                    await onEvent(.failed(sourceID, message))
                case .cancelled:
                    break
                }

                if !Task.isCancelled, let candidate = iterator.next() {
                    addRefresh(candidate, to: &group)
                }
            }
        }
    }

    private func runLoop(id: UUID) async {
        while !Task.isCancelled, loopID == id {
            let scheduledAt = (await clock.now()).addingTimeInterval(interval.timeInterval)
            nextRunAt = scheduledAt
            await onEvent(.scheduled(scheduledAt))
            do {
                try await clock.sleep(for: interval)
            } catch {
                break
            }
            guard !Task.isCancelled, loopID == id else { break }
            await runDueRefresh(referenceDate: await clock.now())
        }

        if loopID == id {
            loopID = nil
            loopTask = nil
            nextRunAt = nil
        }
    }

    private func addRefresh(
        _ record: ConnectorRecord,
        to group: inout TaskGroup<RefreshOutcome>
    ) {
        let refresh = self.refresh
        let onEvent = self.onEvent
        group.addTask {
            guard !Task.isCancelled else { return .cancelled }
            await onEvent(.started(record.id))
            do {
                try Task.checkCancellation()
                let refreshed = try await refresh(record)
                return .succeeded(record.id, refreshed.documentCount)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(record.id, error.localizedDescription)
            }
        }
    }

    private func isRefreshEligible(_ record: ConnectorRecord) -> Bool {
        switch record.status {
        case .ready, .syncing, .failed:
            true
        case .paused, .needsAuthorization:
            false
        }
    }
}

private enum RefreshOutcome: Sendable {
    case succeeded(UUID, Int)
    case failed(UUID, String)
    case cancelled
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
