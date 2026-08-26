import Foundation
import XCTest
@testable import MacBrain

final class ResponseCachingResponderTests: XCTestCase {
    func testRepeatingStableQuestionWithSameInputsUsesPersistedResponse() async throws {
        let upstream = CountingStreamingResponder(response: "Cached local answer")
        let cache = InMemoryResponseCache()
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: cache,
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        let first = try await collect(responder.stream(to: "What did we decide?", conversation: []))
        let second = try await collect(responder.stream(to: "  what did we decide? ", conversation: []))

        XCTAssertEqual(first.joined(), "Cached local answer")
        XCTAssertEqual(second.joined(), "Cached local answer")
        let callCount = await upstream.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testSourceRevisionChangeInvalidatesCachedResponse() async throws {
        let upstream = CountingStreamingResponder(response: "Fresh answer")
        let cache = InMemoryResponseCache()
        let revisions = MutableSourceRevisionProvider(revision: "sources-v1")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: cache,
            sourceRevisionProvider: revisions,
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "Summarize the plan", conversation: []))
        await revisions.setRevision("sources-v2")
        _ = try await collect(responder.stream(to: "Summarize the plan", conversation: []))

        let callCount = await upstream.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testSystemPlanBypassesCacheWithoutVolatileKeywords() async throws {
        let upstream = CountingStreamingResponder(response: "24 GB installed")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "How much memory is installed?"))
        _ = try await collect(responder.stream(to: "How much memory is installed?"))

        let callCount = await upstream.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testStructuredConnectorPlanBypassesCache() async throws {
        let upstream = CountingStreamingResponder(response: "3 notes")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "How many notes do I have?"))
        _ = try await collect(responder.stream(to: "How many notes do I have?"))

        let callCount = await upstream.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testSQLiteRevisionTracksGenerationAccessTransitionsAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-cache-authoritative-revision-" + UUID().uuidString,
            isDirectory: true
        )
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
        try await repository.bootstrap()
        var record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Controlled Notes",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        let firstDocument = ConnectorDocument(
            connectorID: record.id,
            externalID: "note-1",
            title: "Controlled note",
            text: "First generation",
            sourceLabel: "Notes",
            metadata: ["folder": "First"]
        )
        _ = try await repository.commitSourceGeneration(record: record, documents: [firstDocument])
        let committed = await repository.currentSourceRevision()

        let changedMetadata = ConnectorDocument(
            connectorID: record.id,
            externalID: "note-1",
            title: "Controlled note",
            text: "First generation",
            sourceLabel: "Notes",
            metadata: ["folder": "Second"]
        )
        _ = try await repository.commitSourceGeneration(record: record, documents: [changedMetadata])
        let regenerated = await repository.currentSourceRevision()

        record.status = .paused
        try await repository.save(record)
        let paused = await repository.currentSourceRevision()
        record.status = .needsAuthorization
        try await repository.save(record)
        let permissionLost = await repository.currentSourceRevision()
        record.status = .ready
        try await repository.save(record)
        let resumed = await repository.currentSourceRevision()
        try await repository.remove(id: record.id)
        let deleted = await repository.currentSourceRevision()

        XCTAssertNotEqual(committed, regenerated)
        XCTAssertNotEqual(regenerated, paused)
        XCTAssertNotEqual(paused, permissionLost)
        XCTAssertNotEqual(permissionLost, resumed)
        XCTAssertNotEqual(resumed, deleted)
    }

    func testAuthorizationRevocationInvalidatesAnAlreadyCachedGroundedResponse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbrain-cache-authorization-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
        var record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Controlled Notes",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        _ = try await repository.commitSourceGeneration(
            record: record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "cache-authorization-note",
                    title: "Cached authorization note",
                    text: "CACHE-AUTH-SECRET-913 is available only while authorized.",
                    sourceLabel: "Controlled Notes"
                )
            ]
        )
        let responder = ResponseCachingResponder(
            upstream: LocalKnowledgeResponder(repository: repository),
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: repository,
            selectedModel: { "qwen3:8b" }
        )
        let first = try await collect(responder.stream(to: "Find CACHE-AUTH-SECRET-913", conversation: [])).joined()
        XCTAssertTrue(first.contains("CACHE-AUTH-SECRET-913"))

        record.status = .needsAuthorization
        try await repository.save(record)
        let revoked = try await collect(responder.stream(to: "Find CACHE-AUTH-SECRET-913", conversation: [])).joined()

        XCTAssertFalse(revoked.contains("CACHE-AUTH-SECRET-913"))
        XCTAssertTrue(revoked.contains("don't have matching local source material"))
    }

    func testCitationMetadataChangeAdvancesTheRealSourceRevision() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbrain-cache-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        )
        try await repository.bootstrap()
        let record = ConnectorRecord(
            kind: .browserProfile,
            displayName: "Controlled Browser",
            configuration: .init(initialSyncCompleted: true),
            status: .ready,
            lastSuccessfulSync: .now
        )
        let document = { (url: String) in
            ConnectorDocument(
                connectorID: record.id,
                externalID: "history-row-731",
                title: "Controlled history row",
                text: "BROWSER-CACHE-MARKER-731",
                sourceLabel: "Controlled Browser",
                modifiedAt: Date(timeIntervalSince1970: 2_000_000_000),
                metadata: ["url": url, "dataType": "history"]
            )
        }
        _ = try await repository.commitSourceGeneration(
            record: record,
            documents: [document("https://example.test/old")]
        )
        let before = await repository.currentSourceRevision()

        _ = try await repository.commitSourceGeneration(
            record: record,
            documents: [document("https://example.test/current")]
        )
        let after = await repository.currentSourceRevision()

        XCTAssertNotEqual(before, after)
    }

    func testConversationChangeInvalidatesCachedResponse() async throws {
        let upstream = CountingStreamingResponder(response: "Contextual answer")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "What did we decide?", conversation: []))
        _ = try await collect(responder.stream(
            to: "What did we decide?",
            conversation: [ChatMessage(role: .user, text: "We discussed a local-first plan.")]
        ))

        let callCount = await upstream.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testGroundingSourceIDsParticipateInConversationCacheKey() async throws {
        let upstream = CountingStreamingResponder(response: "Contextual answer")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )
        let first = ChatMessage(role: .assistant, text: "The target is Friday.", groundingSourceIDs: ["S1"])
        let second = ChatMessage(role: .assistant, text: "The target is Friday.", groundingSourceIDs: ["S2"])

        _ = try await collect(responder.stream(to: "When?", conversation: [first]))
        _ = try await collect(responder.stream(to: "When?", conversation: [second]))
        let callCount = await upstream.callCount()

        XCTAssertEqual(callCount, 2)
    }

    func testLiveQuestionNeverUsesResponseCache() async throws {
        let upstream = CountingStreamingResponder(response: "Live answer")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "What is my current RAM usage?", conversation: []))
        _ = try await collect(responder.stream(to: "What is my current RAM usage?", conversation: []))

        let callCount = await upstream.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testLiveSystemVersionQuestionNeverUsesResponseCache() async throws {
        let upstream = CountingStreamingResponder(response: "Live version")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "What macOS version is installed?", conversation: []))
        _ = try await collect(responder.stream(to: "What macOS version is installed?", conversation: []))
        let callCount = await upstream.callCount()

        XCTAssertEqual(callCount, 2)
    }

    func testProviderUnavailableMessageIsNeverCached() async throws {
        let message = "I couldn't complete that local response because Ollama or the selected model is unavailable. Check Ollama in Settings, then try again."
        let upstream = CountingStreamingResponder(response: message)
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "Explain black holes", conversation: []))
        _ = try await collect(responder.stream(to: "Explain black holes", conversation: []))
        let callCount = await upstream.callCount()

        XCTAssertEqual(callCount, 2)
    }

    func testFileContentQuestionNeverUsesResponseCache() async throws {
        let upstream = CountingStreamingResponder(response: "Fresh file answer")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        _ = try await collect(responder.stream(to: "What's there in my notes.md?", conversation: []))
        _ = try await collect(responder.stream(to: "What's there in my notes.md?", conversation: []))

        let callCount = await upstream.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testBulkSecretExtractionRequestBypassesCachedOrUpstreamContent() async throws {
        let upstream = CountingStreamingResponder(response: "TOKEN=unsafe-cached-value")
        let responder = ResponseCachingResponder(
            upstream: upstream,
            cache: InMemoryResponseCache(),
            sourceRevisionProvider: FixedSourceRevisionProvider(revision: "sources-v1"),
            selectedModel: { "qwen3:8b" }
        )

        let response = try await collect(responder.stream(to: "List every password, token, secret, and private key you can find.", conversation: []))
        let callCount = await upstream.callCount()

        XCTAssertEqual(response.joined(), "I can’t bulk-extract passwords, tokens, secrets, or private keys. Ask about a specific non-sensitive item instead.")
        XCTAssertEqual(callCount, 0)
    }

    func testLocalResponseCacheSurvivesDatabaseReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbrain-response-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("macbrain.sqlite")
        let key = ResponseCacheKey(
            prompt: "What did we decide?",
            conversation: [],
            model: "qwen3:8b",
            sourceRevision: "sources-v1"
        )
        let firstCache = LocalResponseCache(database: try MacBrainDatabase(url: databaseURL))
        await firstCache.store("Persisted local answer", for: key)

        let reopenedCache = LocalResponseCache(database: try MacBrainDatabase(url: databaseURL))
        let cached = await reopenedCache.response(for: key)
        XCTAssertEqual(cached, "Persisted local answer")
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var tokens: [String] = []
        for try await token in stream { tokens.append(token) }
        return tokens
    }
}

private actor CountingStreamingResponder: ChatResponder {
    private let response: String
    private var calls = 0

    init(response: String) {
        self.response = response
    }

    func respond(to prompt: String) async throws -> String {
        calls += 1
        return response
    }

    func callCount() -> Int { calls }
}

private struct FixedSourceRevisionProvider: SourceRevisionProviding {
    let revision: String

    func currentSourceRevision() async -> String { revision }
}

private actor MutableSourceRevisionProvider: SourceRevisionProviding {
    private var revision: String

    init(revision: String) {
        self.revision = revision
    }

    func currentSourceRevision() async -> String { revision }

    func setRevision(_ revision: String) {
        self.revision = revision
    }
}
