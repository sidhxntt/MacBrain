import Foundation
import Testing
@testable import MacBrain

struct FreshInstallConnectorE2ETests {
    @Test("Fresh install connects, indexes, answers, counts, and restarts without source mutation")
    func connectSyncAskAndRestartRequiresNoSourceEdit() async throws {
        let connector = ScriptedFreshInstallConnector(
            kind: .appleNotes,
            outcomes: [
                .documents([
                    .init(
                        externalID: "preexisting-aurora-731",
                        title: "Preexisting Aurora decision",
                        text: "AURORA-PREEXISTING-731 owner: Riya Sen",
                        sourceLabel: "Apple Notes"
                    )
                ])
            ]
        )
        let app = try await FreshInstallConnectorFixture(connectors: [connector])
        defer { app.removeTemporaryFiles() }

        #expect(await app.repository.allRecords().isEmpty)
        let created = try await app.coordinator.create(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )
        #expect(created.status == .syncing)
        #expect(await app.repository.verifiedIndexHealth(for: created.id) == nil)

        let synced = try await app.coordinator.sync(id: created.id)
        let health = try #require(await app.repository.verifiedIndexHealth(for: created.id))
        #expect(synced.status == .ready)
        #expect(health.isSearchable)
        #expect(health.documentCount == 1)
        #expect(await connector.sourceMutationCount == 0)

        let answer = try await app.ask("Who owns AURORA-PREEXISTING-731?")
        #expect(answer.contains("Riya Sen"))
        #expect(answer.contains("[S1]"))
        #expect(answer.contains("### Sources"))

        let count = try await app.ask("How many notes do I have?")
        #expect(count.contains("There are 1 note"))

        let capability = try await app.ask("Can you read my notes from Apple Notes?")
        #expect(capability.contains("connected locally and ready to search"))

        let relaunched = try await app.relaunched()
        let restartCount = try await relaunched.ask("How many notes do I have?")
        let restartAnswer = try await relaunched.ask("Who owns AURORA-PREEXISTING-731?")
        #expect(restartCount.contains("There are 1 note"))
        #expect(restartAnswer.contains("Riya Sen"))
        #expect(await connector.sourceMutationCount == 0)
    }

    @Test("A connected empty source becomes verified empty and answers deterministically")
    func verifiedEmptySourceIsReadyWithoutAnEdit() async throws {
        let connector = ScriptedFreshInstallConnector(
            kind: .appleNotes,
            outcomes: [.documents([])]
        )
        let app = try await FreshInstallConnectorFixture(connectors: [connector])
        defer { app.removeTemporaryFiles() }

        let record = try await app.connect(.appleNotes)
        let health = try #require(await app.repository.verifiedIndexHealth(for: record.id))

        #expect(record.status == .ready)
        #expect(health.isEmpty)
        #expect(await connector.sourceMutationCount == 0)
        #expect(try await app.ask("How many notes do I have?") == "Apple Notes has a verified searchable index with 0 notes.")
        #expect(try await app.ask("Can you read my Apple Notes?").contains("connected and synced"))
    }

    @Test("Permission loss and deletion immediately isolate previously verified content")
    func permissionAndRemovalIsolation() async throws {
        let connector = ScriptedFreshInstallConnector(
            kind: .appleNotes,
            outcomes: [
                .documents([
                    .init(
                        externalID: "private-zenith-918",
                        title: "Private Zenith note",
                        text: "ZENITH-PRIVATE-918 owner: Ava Rao",
                        sourceLabel: "Apple Notes"
                    )
                ])
            ]
        )
        let app = try await FreshInstallConnectorFixture(connectors: [connector])
        defer { app.removeTemporaryFiles() }
        var record = try await app.connect(.appleNotes)
        #expect(try await app.ask("Who owns ZENITH-PRIVATE-918?").contains("Ava Rao"))

        record.status = .needsAuthorization
        record.lastError = "Controlled permission loss"
        try await app.repository.save(record)

        let revokedAnswer = try await app.ask("Who owns ZENITH-PRIVATE-918?")
        let revokedCount = try await app.ask("How many notes do I have?")
        let revokedCapability = try await app.ask("Can you read my Apple Notes?")
        #expect(revokedAnswer.contains("Ava Rao") == false)
        #expect(revokedAnswer.contains("ZENITH-PRIVATE-918") == false)
        #expect(revokedCount.contains("needs permission and is not searchable"))
        #expect(revokedCapability.contains("unavailable until you reauthorize"))

        try await app.coordinator.remove(id: record.id)
        let removedCount = try await app.ask("How many notes do I have?")
        let removedAnswer = try await app.ask("Who owns ZENITH-PRIVATE-918?")
        #expect(removedCount.contains("isn’t connected"))
        #expect(removedAnswer.contains("Ava Rao") == false)
        #expect(ChatCitationCard.parse(from: removedAnswer).isEmpty)
    }

    @Test("Five-minute refresh keeps old generation searchable and isolates a sibling failure")
    func refreshWhileChattingAndFailureIsolation() async throws {
        let notes = ScriptedFreshInstallConnector(
            kind: .appleNotes,
            outcomes: [
                .documents([
                    .init(
                        externalID: "refresh-note",
                        title: "Refresh note",
                        text: "REFRESH-STABLE-731 owner: Riya Sen",
                        sourceLabel: "Apple Notes"
                    )
                ]),
                .blockedDocuments([
                    .init(
                        externalID: "refresh-note",
                        title: "Refresh note",
                        text: "REFRESH-NEW-842 owner: Nila Quill",
                        sourceLabel: "Apple Notes"
                    )
                ])
            ]
        )
        let calendar = ScriptedFreshInstallConnector(
            kind: .calendar,
            outcomes: [
                .documents([
                    .init(
                        externalID: "calendar-stable",
                        title: "Stable planning event",
                        text: "CALENDAR-STABLE-284 location: Atlas Room",
                        sourceLabel: "Calendar"
                    )
                ]),
                .failure("Controlled Calendar refresh failure")
            ]
        )
        let app = try await FreshInstallConnectorFixture(connectors: [notes, calendar])
        defer { app.removeTemporaryFiles() }
        let noteRecord = try await app.connect(.appleNotes)
        let calendarRecord = try await app.connect(.calendar)
        let referenceDate = max(
            noteRecord.lastSuccessfulSync ?? .distantPast,
            calendarRecord.lastSuccessfulSync ?? .distantPast
        ).addingTimeInterval(300)
        let scheduler = ConnectorRefreshScheduler(
            interval: .seconds(300),
            maximumConcurrentRefreshes: 2,
            loadCandidates: { await app.repository.allRecords() },
            refresh: { record in try await app.coordinator.sync(id: record.id) }
        )

        let refresh = Task {
            await scheduler.runDueRefresh(referenceDate: referenceDate)
        }
        await notes.waitForInvocation(count: 2)

        let duringRefresh = try await app.ask("Who owns REFRESH-STABLE-731?")
        #expect(duringRefresh.contains("Riya Sen"))
        #expect(duringRefresh.contains("[S1]"))

        await notes.releaseBlockedSync()
        await refresh.value

        let refreshed = try await app.ask("Who owns REFRESH-NEW-842?")
        let failedSibling = try await app.ask("Where is CALENDAR-STABLE-284?")
        let savedCalendar = try #require(await app.repository.record(id: calendarRecord.id))
        #expect(refreshed.contains("Nila Quill"))
        #expect(failedSibling.contains("Atlas Room"))
        #expect(savedCalendar.status == .failed)
        #expect(await app.repository.verifiedIndexHealth(for: calendarRecord.id)?.isSearchable == true)
        #expect(await notes.invocationCount == 2)
        #expect(await calendar.invocationCount == 2)
    }

    @Test("Semantic timeout preserves the first verified lexical generation")
    func semanticTimeoutPreservesFreshInstallEvidence() async throws {
        let connector = ScriptedFreshInstallConnector(
            kind: .appleNotes,
            outcomes: [
                .documents([
                    .init(
                        externalID: "timeout-orbit-731",
                        title: "ORBIT-731 launch handoff",
                        text: "ORBIT-731 owner: Nila Quill",
                        sourceLabel: "Apple Notes"
                    )
                ])
            ]
        )
        let provider = FreshInstallProbeProvider(
            status: .ready(models: [
                .init(
                    name: "controlled-chat",
                    size: nil,
                    parameterSize: "test",
                    quantization: "test"
                )
            ]),
            answer: "Nila Quill owns ORBIT-731. [S1]",
            stallsEmbeddings: true
        )
        let app = try await FreshInstallConnectorFixture(
            connectors: [connector],
            provider: provider,
            retrievalTimeout: .milliseconds(20)
        )
        defer { app.removeTemporaryFiles() }
        _ = try await app.connect(.appleNotes)
        let startedAt = ContinuousClock.now

        let answer = try await app.ask("Who owns ORBIT-731?")

        #expect(answer.contains("Nila Quill"))
        #expect(answer.contains("[S1]"))
        #expect(startedAt.duration(to: .now) < .milliseconds(250))
        #expect(provider.embeddingCallCount == 1)
        #expect(provider.streamCallCount == 1)
    }
}

private struct FreshInstallDocumentTemplate: Sendable {
    let externalID: String
    let title: String
    let text: String
    let sourceLabel: String

    func document(connectorID: UUID) -> ConnectorDocument {
        ConnectorDocument(
            connectorID: connectorID,
            externalID: externalID,
            title: title,
            text: text,
            sourceLabel: sourceLabel,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }
}

private actor ScriptedFreshInstallConnector: SourceConnector {
    enum Outcome: Sendable {
        case documents([FreshInstallDocumentTemplate])
        case blockedDocuments([FreshInstallDocumentTemplate])
        case failure(String)
    }

    nonisolated let kind: SourceConnectorKind
    private let outcomes: [Outcome]
    private var invocationTotal = 0
    private var invocationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    init(kind: SourceConnectorKind, outcomes: [Outcome]) {
        self.kind = kind
        self.outcomes = outcomes
    }

    var invocationCount: Int { invocationTotal }
    var sourceMutationCount: Int { 0 }

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        let index = invocationTotal
        invocationTotal += 1
        resumeInvocationWaiters()
        let outcome = outcomes[min(index, outcomes.count - 1)]
        switch outcome {
        case .documents(let templates):
            return templates.map { $0.document(connectorID: record.id) }
        case .blockedDocuments(let templates):
            await withCheckedContinuation { continuation in
                blockedWaiters.append(continuation)
            }
            try Task.checkCancellation()
            return templates.map { $0.document(connectorID: record.id) }
        case .failure(let message):
            throw ConnectorError.failed(message)
        }
    }

    func waitForInvocation(count: Int) async {
        if invocationTotal >= count { return }
        await withCheckedContinuation { continuation in
            invocationWaiters.append((count, continuation))
        }
    }

    func releaseBlockedSync() {
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func resumeInvocationWaiters() {
        let ready = invocationWaiters.filter { $0.0 <= invocationTotal }
        invocationWaiters.removeAll { $0.0 <= invocationTotal }
        for (_, waiter) in ready { waiter.resume() }
    }
}

private struct FreshInstallConnectorFixture {
    let directory: URL
    let sourceFileURL: URL
    let databaseURL: URL
    let repository: LocalSourceRepository
    let coordinator: LocalSourceCoordinator
    let provider: FreshInstallProbeProvider
    let retrievalTimeout: Duration

    init(
        connectors: [any SourceConnector],
        provider: FreshInstallProbeProvider = FreshInstallProbeProvider(),
        retrievalTimeout: Duration = .milliseconds(100)
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacBrainFreshInstall-" + UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceFileURL = directory.appendingPathComponent("local-sources.json")
        let databaseURL = directory.appendingPathComponent("macbrain.sqlite")
        let database = try MacBrainDatabase(url: databaseURL)
        let repository = LocalSourceRepository(fileURL: sourceFileURL, database: database)
        try await repository.bootstrap()

        self.directory = directory
        self.sourceFileURL = sourceFileURL
        self.databaseURL = databaseURL
        self.repository = repository
        self.coordinator = LocalSourceCoordinator(
            repository: repository,
            syncTimeout: .seconds(2),
            connectors: connectors
        )
        self.provider = provider
        self.retrievalTimeout = retrievalTimeout
    }

    private init(
        directory: URL,
        sourceFileURL: URL,
        databaseURL: URL,
        repository: LocalSourceRepository,
        provider: FreshInstallProbeProvider,
        retrievalTimeout: Duration
    ) {
        self.directory = directory
        self.sourceFileURL = sourceFileURL
        self.databaseURL = databaseURL
        self.repository = repository
        self.coordinator = LocalSourceCoordinator(repository: repository, connectors: [])
        self.provider = provider
        self.retrievalTimeout = retrievalTimeout
    }

    func connect(_ kind: SourceConnectorKind) async throws -> ConnectorRecord {
        let record = try await coordinator.create(
            kind: kind,
            displayName: kind.displayName,
            configuration: .init()
        )
        return try await coordinator.sync(id: record.id)
    }

    func ask(_ prompt: String) async throws -> String {
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "controlled-chat" },
            selectedEmbeddingModel: { "controlled-embedding" },
            fallback: FreshInstallFallbackResponder(),
            systemProfileProvider: FreshInstallProfileProvider(),
            providerStatusTimeout: .milliseconds(100),
            retrievalTimeout: retrievalTimeout
        )
        var answer = ""
        for try await token in responder.stream(to: prompt) { answer.append(token) }
        return answer
    }

    func relaunched() async throws -> FreshInstallConnectorFixture {
        let repository = LocalSourceRepository(
            fileURL: sourceFileURL,
            database: try MacBrainDatabase(url: databaseURL)
        )
        try await repository.bootstrap()
        return FreshInstallConnectorFixture(
            directory: directory,
            sourceFileURL: sourceFileURL,
            databaseURL: databaseURL,
            repository: repository,
            provider: provider,
            retrievalTimeout: retrievalTimeout
        )
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class FreshInstallProbeProvider: InferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let statusValue: InferenceProviderStatus
    private let answer: String
    private let stallsEmbeddings: Bool
    private var embeddingCalls = 0
    private var streamCalls = 0

    init(
        status: InferenceProviderStatus = .runtimeMissing,
        answer: String = "This must not be generated.",
        stallsEmbeddings: Bool = false
    ) {
        statusValue = status
        self.answer = answer
        self.stallsEmbeddings = stallsEmbeddings
    }

    var embeddingCallCount: Int { lock.withLock { embeddingCalls } }
    var streamCallCount: Int { lock.withLock { streamCalls } }

    func status() async -> InferenceProviderStatus { statusValue }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        lock.withLock { embeddingCalls += 1 }
        if stallsEmbeddings {
            return await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    continuation.resume(returning: input.map { _ in .init(values: [1, 0]) })
                }
            }
        }
        return input.map { _ in .init(values: [1, 0]) }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        lock.withLock { streamCalls += 1 }
        return AsyncThrowingStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }
}

private struct FreshInstallFallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Controlled fallback" }
}

private struct FreshInstallProfileProvider: SystemProfileProviding {
    func currentProfile() -> SystemProfile {
        SystemProfile(
            userDisplayName: "Fresh User",
            computerName: "Fresh Mac",
            hardwareModel: "MacTest,1",
            processor: "Test Processor",
            memoryBytes: 16_000_000_000,
            operatingSystem: "macOS Test",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 500_000_000_000,
            localeIdentifier: "en_US",
            timeZoneIdentifier: "UTC"
        )
    }
}
