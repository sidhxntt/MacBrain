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
