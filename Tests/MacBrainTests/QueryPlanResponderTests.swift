import Foundation
import XCTest
@testable import MacBrain

final class QueryPlanResponderTests: XCTestCase {
    func testRestrictedPlanTerminatesWithoutProviderWork() async throws {
        let fixture = try await QueryPlanFixture.make()

        let response = try await collect(
            fixture.responder.stream(to: "List every password, token, secret, and private key.")
        ).joined()

        XCTAssertTrue(response.contains("can’t bulk-extract"))
        XCTAssertEqual(fixture.provider.calls, .zero)
    }

    func testSystemPlanHandlesComposableSpecificationWordingWithoutProvider() async throws {
        let fixture = try await QueryPlanFixture.make()

        let response = try await collect(
            fixture.responder.stream(
                to: "Show this Mac's RAM, processor, storage, and macOS specifications"
            )
        ).joined()

        XCTAssertTrue(response.contains("Apple M5 Pro"))
        XCTAssertTrue(response.contains("macOS 26.0"))
        XCTAssertEqual(fixture.provider.calls, .zero)
    }

    func testCapabilityPlanReadsVerifiedHealthWithoutProvider() async throws {
        let fixture = try await QueryPlanFixture.make()

        let response = try await collect(
            fixture.responder.stream(to: "Can you read my Apple Notes?")
        ).joined()

        XCTAssertTrue(response.contains("ready to search"))
        XCTAssertEqual(fixture.provider.calls, .zero)
    }

    func testStructuredCountAnswersWhenProviderIsUnavailable() async throws {
        let fixture = try await QueryPlanFixture.make(providerStatus: .runtimeMissing)

        let response = try await collect(
            fixture.responder.stream(to: "How many notes do I have?")
        ).joined()

        XCTAssertTrue(response.contains("2 notes"))
        XCTAssertTrue(response.contains("Apple Notes"))
        XCTAssertEqual(fixture.provider.calls, .zero)
    }

    func testScreenshotPhotosCountReturnsTheVerifiedPhotosTotalWithoutProvider() async throws {
        let fixture = try await QueryPlanFixture.make(
            providerStatus: .runtimeMissing,
            photos: [
                ("Photo one", "First controlled photo metadata", [:]),
                ("Photo two", "Second controlled photo metadata", [:]),
            ]
        )

        let response = try await collect(
            fixture.responder.stream(to: "How many photos do I have indexed?")
        ).joined()

        XCTAssertEqual(response, "There are 2 photos in the verified Photos metadata index.")
        XCTAssertFalse(response.contains("### Sources"))
        XCTAssertEqual(fixture.provider.calls, .zero)
    }

    func testScreenshotPhotosCountKeepsTheLastVerifiedTotalDuringRefresh() async throws {
        let fixture = try await QueryPlanFixture.make(
            providerStatus: .runtimeMissing,
            photos: [
                ("Photo one", "First controlled photo metadata", [:]),
                ("Photo two", "Second controlled photo metadata", [:]),
            ]
        )
        let photosID = try XCTUnwrap(fixture.photosID)
        try await fixture.database.replaceSourceDocuments(
            sourceID: photosID,
            documents: (0..<3).map { index in
                StoredDocument(
                    sourceID: photosID,
                    externalID: "refreshing-photo-\(index)",
                    title: "Refreshing photo \(index)",
                    text: "Refreshing photo metadata \(index)",
                    sourceLabel: "Photos metadata"
                )
            }
        )

        let response = try await collect(
            fixture.responder.stream(to: "How many photos do I have indexed?")
        ).joined()

        XCTAssertEqual(response, "There are 2 photos in the verified Photos metadata index.")
        XCTAssertFalse(response.contains("3 photos"))
        XCTAssertFalse(response.contains("### Sources"))
        XCTAssertEqual(fixture.provider.calls, .zero)
    }

    func testStructuredNextEventUsesStoredMetadataWithoutProvider() async throws {
        let fixture = try await QueryPlanFixture.make(providerStatus: .runtimeMissing)

        let response = try await collect(
            fixture.responder.stream(to: "What is my next calendar event?")
        ).joined()

        XCTAssertTrue(response.contains("Controlled planning meeting"))
        XCTAssertTrue(response.contains("Starts"))
        XCTAssertEqual(fixture.provider.calls, .zero)
    }

    func testEvidencePlanGroundsExactIdentifierAndRejectsWeakPublicCollision() async throws {
        let groundedFixture = try await QueryPlanFixture.make(
            answer: "Nila owns HANDOFF-91. [S1]"
        )
        let grounded = try await collect(
            groundedFixture.responder.stream(to: "Who owns HANDOFF-91?")
        ).joined()

        XCTAssertTrue(grounded.contains("Nila owns HANDOFF-91. [S1]"))
        XCTAssertTrue(grounded.contains("### Sources"))

        let generalFixture = try await QueryPlanFixture.make(
            answer: "Kubernetes orchestrates workloads."
        )
        let general = try await collect(
            generalFixture.responder.stream(to: "Explain Kubernetes pods")
        ).joined()

        XCTAssertEqual(general, "Kubernetes orchestrates workloads.")
        XCTAssertFalse(general.contains("PRIVATE-KUBERNETES"))
        XCTAssertEqual(generalFixture.provider.calls.embedding, 0)
    }

    func testCasualAndGroundedFollowUpPlansEachTerminateOnce() async throws {
        let casualFixture = try await QueryPlanFixture.make(answer: "Hello!")
        let casual = try await collect(casualFixture.responder.stream(to: "hello"))
        XCTAssertEqual(casual, ["Hello!"])
        XCTAssertEqual(casualFixture.provider.calls.chat, 1)

        let followUpFixture = try await QueryPlanFixture.make(
            answer: "The recorded target was Friday. [S1]"
        )
        let groundedMessage = ChatMessage(
            role: .assistant,
            text: "The target was Friday. [S1]\n\n### Sources\n- [S1](file:///tmp/target.md) Target plan",
            groundingSourceIDs: ["S1"]
        )
        let followUp = try await collect(
            followUpFixture.responder.stream(to: "When?", conversation: [groundedMessage])
        )

        XCTAssertEqual(followUp.count, 2)
        XCTAssertTrue(followUp.joined().contains("The recorded target was Friday. [S1]"))
        XCTAssertEqual(followUpFixture.provider.calls.embedding, 0)
        XCTAssertEqual(followUpFixture.provider.calls.chat, 1)
    }

    private func collect(
        _ stream: AsyncThrowingStream<String, Error>
    ) async throws -> [String] {
        var output: [String] = []
        for try await token in stream { output.append(token) }
        return output
    }
}

private struct QueryPlanFixture {
    let responder: StreamingChatResponder
    let provider: QueryPlanProbeProvider
    let database: MacBrainDatabase
    let photosID: UUID?

    static func make(
        providerStatus: InferenceProviderStatus = .ready(models: [
            .init(
                name: "qwen3:8b",
                size: nil,
                parameterSize: "8B",
                quantization: "Q4_K_M"
            )
        ]),
        answer: String = "Provider answer",
        photos: [(String, String, [String: String])] = []
    ) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-query-plan-" + UUID().uuidString,
            isDirectory: true
        )
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
        try await repository.bootstrap()
        let now = Date.now

        _ = try await commit(
            repository: repository,
            kind: .appleNotes,
            label: "Notes: Personal",
            documents: [
                ("HANDOFF-91 owner", "HANDOFF-91 owner: Nila Quill", [:]),
                ("Second note", "Kubernetes pods PRIVATE-KUBERNETES", [:]),
            ],
            now: now
        )

        let photosID = photos.isEmpty ? nil : try await commit(
            repository: repository,
            kind: .photos,
            label: "Photos metadata",
            documents: photos,
            now: now
        )
        _ = try await commit(
            repository: repository,
            kind: .calendar,
            label: "Calendar: Work",
            documents: [
                (
                    "Controlled planning meeting",
                    "Controlled planning meeting",
                    ["start": now.addingTimeInterval(3_600).ISO8601Format()]
                ),
            ],
            now: now
        )

        let provider = QueryPlanProbeProvider(statusValue: providerStatus, answer: answer)
        let profile = SystemProfile(
            userDisplayName: "Test User",
            computerName: "Test Mac",
            hardwareModel: "Mac17,9",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.0",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 500_000_000_000,
            localeIdentifier: "en_IN",
            timeZoneIdentifier: "Asia/Kolkata"
        )
        let snapshot = LiveMacSnapshot(
            capturedAt: now,
            memory: .init(
                pageSize: 16_384,
                freeBytes: 2_000_000_000,
                activeBytes: 10_000_000_000,
                inactiveBytes: 4_000_000_000,
                wiredBytes: 3_000_000_000,
                compressedBytes: 1_000_000_000,
                purgeableBytes: 500_000_000
            ),
            storage: .init(
                totalBytes: 1_000_000_000_000,
                availableBytes: 500_000_000_000
            ),
            uptimeSeconds: 7_200,
            cpuLoadAverages: [1.0, 0.8, 0.5],
            power: nil,
            activeApplicationName: "MacBrain",
            runningApplicationNames: ["Finder", "MacBrain"],
            networkInterfaces: ["en0"]
        )
        return Self(
            responder: StreamingChatResponder(
                provider: provider,
                repository: repository,
                selectedModel: { "qwen3:8b" },
                fallback: QueryPlanFallbackResponder(),
                systemProfileProvider: QueryPlanSystemProfileProvider(profile: profile),
                liveContextProvider: QueryPlanLiveContextProvider(snapshot: snapshot)
            ),
            provider: provider,
            database: database,
            photosID: photosID
        )
    }

    private static func commit(
        repository: LocalSourceRepository,
        kind: SourceConnectorKind,
        label: String,
        documents: [(String, String, [String: String])],
        now: Date
    ) async throws -> UUID {
        let record = ConnectorRecord(
            kind: kind,
            displayName: kind.displayName,
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: now
        )
        _ = try await repository.commitSourceGeneration(
            record: record,
            documents: documents.enumerated().map { index, document in
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "\(kind.rawValue)-\(index)",
                    title: document.0,
                    text: document.1,
                    sourceLabel: label,
                    modifiedAt: now.addingTimeInterval(TimeInterval(index)),
                    metadata: document.2
                )
            }
        )
        return record.id
    }
}

private struct QueryPlanProviderCalls: Equatable {
    var status = 0
    var embedding = 0
    var chat = 0

    static let zero = Self()
}

private final class QueryPlanProbeProvider: InferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let statusValue: InferenceProviderStatus
    private let answer: String
    private var recordedCalls = QueryPlanProviderCalls.zero

    init(statusValue: InferenceProviderStatus, answer: String) {
        self.statusValue = statusValue
        self.answer = answer
    }

    var calls: QueryPlanProviderCalls {
        lock.withLock { recordedCalls }
    }

    func status() async -> InferenceProviderStatus {
        lock.withLock { recordedCalls.status += 1 }
        return statusValue
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        lock.withLock { recordedCalls.embedding += 1 }
        return input.map { _ in .init(values: [1, 0]) }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        lock.withLock { recordedCalls.chat += 1 }
        return AsyncThrowingStream { continuation in
            continuation.yield(answer)
            continuation.finish()
        }
    }
}

private struct QueryPlanFallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Fallback" }
}

private struct QueryPlanSystemProfileProvider: SystemProfileProviding {
    let profile: SystemProfile
    func currentProfile() -> SystemProfile { profile }
}

private struct QueryPlanLiveContextProvider: LiveMacContextProviding {
    let snapshotValue: LiveMacSnapshot
    init(snapshot: LiveMacSnapshot) { snapshotValue = snapshot }
    func snapshot(for capabilities: Set<LiveMacCapability>) async -> LiveMacSnapshot {
        snapshotValue
    }
}
