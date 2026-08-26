import Foundation
import Testing
@testable import MacBrain

struct LocalSourceCapabilityResponderTests {
    @Test("A disconnected Apple Notes capability question explains how to enable it")
    func disconnectedAppleNotesAnswersFromConnectorState() async throws {
        let environment = try CapabilityTestEnvironment()
        defer { environment.removeTemporaryFiles() }
        let provider = CapabilityProbeProvider(tokens: ["This must not be generated."])

        let response = try await collect(
            environment.responder(provider: provider)
                .stream(to: "Can you read my notes from Apple Notes?")
        )

        #expect(response.contains("Apple Notes isn’t connected yet"))
        #expect(response.contains("connect and authorize it"))
        #expect(response.contains("### Sources") == false)
        #expect(provider.callCounts == .zero)
    }

    @Test(
        "Apple Notes capability questions describe every connection state without model access",
        arguments: [
            CapabilityStateCase(status: .ready, verifiedDocumentCount: 2, expectedText: "Apple Notes is connected locally and ready to search"),
            CapabilityStateCase(status: .syncing, verifiedDocumentCount: 2, expectedText: "Apple Notes is connected and refreshing"),
            CapabilityStateCase(status: .needsAuthorization, verifiedDocumentCount: nil, expectedText: "Apple Notes is connected, but macOS permission is needed"),
            CapabilityStateCase(status: .paused, verifiedDocumentCount: 2, expectedText: "Apple Notes is paused"),
            CapabilityStateCase(status: .failed, verifiedDocumentCount: 2, expectedText: "latest Apple Notes sync failed"),
        ]
    )
    func appleNotesStateAnswersWithoutModel(item: CapabilityStateCase) async throws {
        let environment = try CapabilityTestEnvironment()
        defer { environment.removeTemporaryFiles() }
        let provider = CapabilityProbeProvider(tokens: ["This must not be generated."])
        var record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(initialSyncCompleted: item.verifiedDocumentCount != nil),
            status: item.verifiedDocumentCount == nil ? item.status : .ready,
            lastSuccessfulSync: item.verifiedDocumentCount == nil ? nil : .now,
            lastError: item.status == .failed ? "Controlled sync failure" : nil
        )
        if let documentCount = item.verifiedDocumentCount {
            _ = try await environment.repository.commitSourceGeneration(
                record: record,
                documents: (0..<documentCount).map { index in
                    ConnectorDocument(
                        connectorID: record.id,
                        externalID: "verified-\(index)",
                        title: "Verified note \(index)",
                        text: "Verified capability content \(index)",
                        sourceLabel: "Apple Notes"
                    )
                }
            )
            record.status = item.status
            try await environment.repository.save(record)
        } else {
            try await environment.repository.save(record)
        }

        let response = try await collect(
            environment.responder(provider: provider)
                .stream(to: "Can you read my notes from Apple Notes?")
        )

        #expect(response.contains(item.expectedText))
        #expect(response.contains("### Sources") == false)
        #expect(provider.callCounts == .zero)
    }

    @Test("A ready record without verified index health is not called searchable")
    func unverifiedReadyRecordIsNotSearchable() async throws {
        let environment = try CapabilityTestEnvironment()
        defer { environment.removeTemporaryFiles() }
        let provider = CapabilityProbeProvider(tokens: ["This must not be generated."])
        try await environment.repository.save(
            ConnectorRecord(
                kind: .appleNotes,
                displayName: "Apple Notes",
                configuration: .init(),
                status: .ready,
                documentCount: 18
            )
        )

        let response = try await collect(
            environment.responder(provider: provider)
                .stream(to: "Can you read my notes from Apple Notes?")
        )

        #expect(response.contains("first searchable index is still being prepared"))
        #expect(response.contains("isn’t ready to search yet"))
        #expect(provider.callCounts == .zero)
    }

    @Test("Permission loss makes a retained verified index unavailable immediately")
    func revokedSourceDoesNotClaimItsRetainedIndexIsSearchable() async throws {
        let environment = try CapabilityTestEnvironment()
        defer { environment.removeTemporaryFiles() }
        let provider = CapabilityProbeProvider(tokens: ["This must not be generated."])
        var record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        _ = try await environment.repository.commitSourceGeneration(
            record: record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "retained-revoked-note",
                    title: "Retained note",
                    text: "This content is retained but unavailable after permission loss.",
                    sourceLabel: "Apple Notes"
                )
            ]
        )
        record.status = .needsAuthorization
        try await environment.repository.save(record)

        let response = try await collect(
            environment.responder(provider: provider)
                .stream(to: "Can you read my notes from Apple Notes?")
        )

        #expect(response.contains("unavailable until you reauthorize"))
        #expect(response.contains("remains searchable") == false)
        #expect(provider.callCounts == .zero)
    }

    @Test("A verified empty source is connected but explicitly empty")
    func verifiedEmptySourceIsTruthful() async throws {
        let environment = try CapabilityTestEnvironment()
        defer { environment.removeTemporaryFiles() }
        let provider = CapabilityProbeProvider(tokens: ["This must not be generated."])
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        _ = try await environment.repository.commitSourceGeneration(
            record: record,
            documents: []
        )

        let response = try await collect(
            environment.responder(provider: provider)
                .stream(to: "Can you read my notes from Apple Notes?")
        )

        #expect(response.contains("connected and synced"))
        #expect(response.contains("searchable index is empty"))
        #expect(provider.callCounts == .zero)
    }

    @Test("A capability verb paired with a content request keeps the grounded retrieval path")
    func contentBearingCapabilityQuestionStillRetrievesNotes() async throws {
        let environment = try CapabilityTestEnvironment()
        defer { environment.removeTemporaryFiles() }
        let provider = CapabilityProbeProvider(tokens: ["AURORA-NOTES-417 is ready. [S1]"])
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        _ = try await environment.repository.commitSourceGeneration(
            record: record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "capability-aurora-note",
                    title: "Aurora capability note",
                    text: "AURORA-NOTES-417 is ready.",
                    sourceLabel: "Apple Notes"
                )
            ]
        )

        let response = try await collect(
            environment.responder(provider: provider)
                .stream(to: "Can you read my Apple Notes about AURORA-NOTES-417?")
        )

        #expect(response.contains("AURORA-NOTES-417 is ready."))
        #expect(ChatCitationCard.parse(from: response).map(\.citationID) == ["S1"])
        #expect(provider.callCounts.status == 1)
        #expect(provider.callCounts.embeddings == 1)
        #expect(provider.callCounts.streams == 1)
    }
}

struct CapabilityStateCase: Sendable, CustomTestStringConvertible {
    let status: ConnectorStatus
    let verifiedDocumentCount: Int?
    let expectedText: String

    var testDescription: String { status.rawValue }
}

private struct CapabilityTestEnvironment {
    let directory: URL
    let repository: LocalSourceRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBrainCapabilityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        )
    }

    func responder(provider: any InferenceProvider) -> StreamingChatResponder {
        StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "controlled-chat" },
            selectedEmbeddingModel: { "controlled-embedding" },
            fallback: CapabilityFallbackResponder(),
            systemProfileProvider: CapabilitySystemProfileProvider()
        )
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct CapabilityCallCounts: Equatable, Sendable {
    static let zero = Self(status: 0, embeddings: 0, streams: 0)

    let status: Int
    let embeddings: Int
    let streams: Int
}

private final class CapabilityProbeProvider: InferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let tokens: [String]
    private var counts = CapabilityCallCounts.zero

    init(tokens: [String]) {
        self.tokens = tokens
    }

    var callCounts: CapabilityCallCounts {
        lock.withLock { counts }
    }

    func status() async -> InferenceProviderStatus {
        lock.withLock { counts = .init(status: counts.status + 1, embeddings: counts.embeddings, streams: counts.streams) }
        return .ready(models: [InferenceModel(name: "controlled-chat", size: nil, parameterSize: "test", quantization: "test")])
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        lock.withLock { counts = .init(status: counts.status, embeddings: counts.embeddings + 1, streams: counts.streams) }
        return input.map { _ in InferenceEmbedding(values: [1, 0]) }
    }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        lock.withLock { counts = .init(status: counts.status, embeddings: counts.embeddings, streams: counts.streams + 1) }
        return AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct CapabilityFallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Fallback" }
}

private struct CapabilitySystemProfileProvider: SystemProfileProviding {
    func currentProfile() -> SystemProfile {
        SystemProfile(
            userDisplayName: "Controlled User",
            computerName: "Controlled Mac",
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

private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
    var response = ""
    for try await token in stream { response.append(token) }
    return response
}
