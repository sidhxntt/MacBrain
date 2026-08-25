import Foundation
import XCTest
@testable import MacBrain

final class StreamingChatResponderTests: XCTestCase {
    func testReadyProviderStreamsLocalTokens() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: StreamingProvider(statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]), tokens: ["Local", " answer"]),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let tokens = try await collect(responder.stream(to: "What changed?"))

        XCTAssertEqual(tokens, ["Local", " answer"])
    }

    func testUnavailableProviderFallsBackToLocalEvidenceResponder() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: StreamingProvider(statusValue: .runtimeMissing, tokens: []),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let tokens = try await collect(responder.stream(to: "What changed?"))

        XCTAssertEqual(tokens, ["Fallback local answer"])
    }

    func testStalledProviderStatusFallsBackWithoutHoldingTheChat() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: HangingStatusProvider(),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            providerStatusTimeout: .milliseconds(50)
        )

        let clock = ContinuousClock()
        let startedAt = clock.now
        let tokens = try await collect(responder.stream(to: "What changed?"))

        XCTAssertEqual(tokens, ["Fallback local answer"])
        XCTAssertLessThan(startedAt.duration(to: .now), .seconds(1))
    }

    func testReadyProviderReceivesLocalSystemProfileAndGeneralAnswerGuidance() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let profile = SystemProfile(
            userDisplayName: "Siddhant Gupta",
            computerName: "Siddhant’s MacBook Pro",
            hardwareModel: "Mac16,7",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.0 (Build 25A123)",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN",
            timeZoneIdentifier: "Asia/Kolkata"
        )
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            systemProfileProvider: FixedSystemProfileProvider(profile: profile)
        )

        _ = try await collect(responder.stream(to: "Who am I and what Mac am I using?"))

        let systemInstruction = try XCTUnwrap(provider.messages.first(where: { $0.role == .system })?.content)
        XCTAssertTrue(systemInstruction.contains("Siddhant Gupta"))
        XCTAssertTrue(systemInstruction.contains("Apple M5 Pro"))
        XCTAssertTrue(systemInstruction.contains("Answer ordinary questions directly"))
        XCTAssertTrue(systemInstruction.contains("Use concise Markdown"))
    }

    func testLiveMemoryQuestionReturnsSnapshotWithoutCallingInferenceProvider() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let profile = SystemProfile(
            userDisplayName: "Siddhant Gupta",
            computerName: "Siddhant’s MacBook Pro",
            hardwareModel: "Mac17,9",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.6.2",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN",
            timeZoneIdentifier: "Asia/Kolkata",
            memoryUsage: SystemMemoryUsage(
                pageSize: 16_384,
                freeBytes: 2_000_000_000,
                activeBytes: 10_000_000_000,
                inactiveBytes: 4_000_000_000,
                wiredBytes: 3_000_000_000,
                compressedBytes: 1_000_000_000,
                purgeableBytes: 500_000_000
            )
        )
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            systemProfileProvider: FixedSystemProfileProvider(profile: profile)
        )

        let response = try await collect(responder.stream(to: "How much RAM is free right now? Give me a full breakdown."))

        XCTAssertTrue(response.joined().contains("## Memory now"))
        XCTAssertTrue(provider.messages.isEmpty)
    }

    func testIdentityQuestionReturnsLocalSystemProfileWithoutCallingInferenceProvider() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            systemProfileProvider: FixedSystemProfileProvider(profile: liveProfile()),
            minimumLiveResponseDelay: .zero
        )

        let response = try await collect(responder.stream(to: "Who am I?"))

        XCTAssertTrue(response.joined().contains("## Your Mac"))
        XCTAssertTrue(response.joined().contains("Siddhant Gupta"))
        XCTAssertTrue(provider.messages.isEmpty)
    }

    func testLiveStorageQuestionBypassesSourceSearchAndInference() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            systemProfileProvider: FixedSystemProfileProvider(profile: liveProfile()),
            liveContextProvider: FixedLiveMacContextProvider(snapshot: liveSnapshot())
        )

        let response = try await collect(responder.stream(to: "How much disk space is available right now?"))

        XCTAssertTrue(response.joined().contains("## Storage now"))
        XCTAssertTrue(provider.messages.isEmpty)
    }

    func testFileContentQuestionReadsFreshApprovedFolderContentWithoutInference() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbrain-file-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("notes.md")
        try Data("# Notes\nOriginal indexed text".utf8).write(to: fileURL)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(fileURL: directory.appendingPathComponent("sources.json"), database: database)
        let record = ConnectorRecord(
            kind: .folder,
            displayName: "Test folder",
            configuration: .init(localPath: directory.path)
        )
        try await repository.save(record)
        _ = try await repository.replaceDocuments(for: record.id, with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: fileURL.path,
                title: "Notes",
                text: "# Notes\nOriginal indexed text",
                sourceLabel: "Test folder",
                metadata: ["path": fileURL.path, "relativePath": "notes.md"]
            )
        ])
        try Data("# Notes\nFresh file content".utf8).write(to: fileURL)

        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "What's there in my notes.md?"))

        XCTAssertTrue(response.joined().contains("Fresh file content"))
        XCTAssertFalse(response.joined().contains("Original indexed text"))
        XCTAssertTrue(provider.messages.isEmpty)
    }

    private func liveProfile() -> SystemProfile {
        SystemProfile(
            userDisplayName: "Siddhant Gupta", computerName: "Siddhant’s MacBook Pro", hardwareModel: "Mac17,9", processor: "Apple M5 Pro", memoryBytes: 24_000_000_000, operatingSystem: "macOS 26.6.2", totalDiskBytes: 1_000_000_000_000, availableDiskBytes: 512_000_000_000, localeIdentifier: "en_IN", timeZoneIdentifier: "Asia/Kolkata"
        )
    }

    private func liveSnapshot() -> LiveMacSnapshot {
        LiveMacSnapshot(
            capturedAt: .now,
            memory: .init(pageSize: 16_384, freeBytes: 2_000_000_000, activeBytes: 10_000_000_000, inactiveBytes: 4_000_000_000, wiredBytes: 3_000_000_000, compressedBytes: 1_000_000_000, purgeableBytes: 500_000_000),
            storage: .init(totalBytes: 1_000_000_000_000, availableBytes: 512_000_000_000),
            uptimeSeconds: 7_200,
            cpuLoadAverages: [1.2, 0.8, 0.6],
            power: nil,
            activeApplicationName: "MacBrain",
            runningApplicationNames: ["Finder", "MacBrain"],
            networkInterfaces: ["en0"]
        )
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var tokens: [String] = []
        for try await token in stream { tokens.append(token) }
        return tokens
    }

    private func temporaryRepositoryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sources.json")
    }
}

private struct StreamingProvider: InferenceProvider {
    let statusValue: InferenceProviderStatus
    let tokens: [String]

    func status() async -> InferenceProviderStatus { statusValue }
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }
}

private struct HangingStatusProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus {
        try? await Task.sleep(for: .seconds(3_600))
        return .runtimeMissing
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }
    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
}

private struct FallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Fallback local answer" }
}

private struct FixedSystemProfileProvider: SystemProfileProviding {
    let profile: SystemProfile

    func currentProfile() -> SystemProfile { profile }
}

private struct FixedLiveMacContextProvider: LiveMacContextProviding {
    let snapshot: LiveMacSnapshot

    func snapshot(for capabilities: Set<LiveMacCapability>) async -> LiveMacSnapshot { snapshot }
}

private final class CapturingStreamingProvider: InferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedMessages: [InferenceChatMessage] = []

    var messages: [InferenceChatMessage] {
        lock.lock()
        defer { lock.unlock() }
        return capturedMessages
    }

    func status() async -> InferenceProviderStatus {
        .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")])
    }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        lock.lock()
        capturedMessages = messages
        lock.unlock()
        return AsyncThrowingStream { continuation in
            continuation.yield("Local answer")
            continuation.finish()
        }
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }
}
