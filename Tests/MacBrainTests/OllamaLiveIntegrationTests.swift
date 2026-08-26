import Foundation
import XCTest
@testable import MacBrain

final class OllamaLiveIntegrationTests: XCTestCase {
    private static var chatModel: String {
        ProcessInfo.processInfo.environment["MACBRAIN_LIVE_CHAT_MODEL"] ?? "qwen3:8b"
    }

    private static var embeddingModel: String {
        ProcessInfo.processInfo.environment["MACBRAIN_LIVE_EMBEDDING_MODEL"] ?? "nomic-embed-text"
    }

    func testLocalOllamaServesConfiguredModelsEmbeddingAndVisibleChatTokens() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_LIVE_OLLAMA"] == "1",
            "Set MACBRAIN_LIVE_OLLAMA=1 to exercise the local Ollama service."
        )

        let client = OllamaClient(retryLimit: 0)
        try await client.health()

        let models = try await client.models().map(\.name)
        XCTAssertTrue(models.contains(Self.chatModel))
        XCTAssertTrue(models.contains(Self.embeddingModel))

        let vectors = try await client.embeddings(model: Self.embeddingModel, input: ["MacBrain integration test"])
        XCTAssertEqual(vectors.count, 1)
        XCTAssertFalse(vectors[0].isEmpty)

        var response = ""
        for try await token in client.streamChat(
            model: Self.chatModel,
            messages: [.user("Reply with exactly: MacBrain ready")]
        ) {
            response += token
        }

        XCTAssertFalse(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testLocalOllamaCanAnswerFromInjectedMacContext() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_LIVE_OLLAMA"] == "1",
            "Set MACBRAIN_LIVE_OLLAMA=1 to exercise the local Ollama service."
        )

        let profile = SystemProfile(
            userDisplayName: "Alex",
            computerName: "Alex’s MacBook Pro",
            hardwareModel: "Mac16,7",
            processor: "Apple M5 Pro",
            memoryBytes: 24_000_000_000,
            operatingSystem: "macOS 26.0 (Build 25A123)",
            totalDiskBytes: 1_000_000_000_000,
            availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN",
            timeZoneIdentifier: "Asia/Kolkata"
        )
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: OllamaProvider(client: OllamaClient(retryLimit: 0, firstTokenTimeout: .seconds(20))),
            repository: repository,
            selectedModel: { Self.chatModel },
            fallback: LocalMockChatResponder(),
            systemProfileProvider: LiveTestSystemProfileProvider(profile: profile)
        )

        var response = ""
        for try await token in responder.stream(to: "Using the supplied device context, reply with only the processor name.") {
            response += token
        }

        XCTAssertTrue(response.localizedCaseInsensitiveContains("M5 Pro"))
    }

    func testLocalOllamaGroundsASyntheticConnectedSource() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_LIVE_OLLAMA"] == "1",
            "Set MACBRAIN_LIVE_OLLAMA=1 to exercise the local Ollama service."
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBrainLiveGrounding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
        let record = ConnectorRecord(kind: .folder, displayName: "Synthetic live fixture", configuration: .init())
        try await repository.save(record)
        _ = try await repository.replaceDocuments(for: record.id, with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "aurora-live.md",
                title: "Aurora beta decision",
                text: "Riya Sen owns the Aurora beta decision. The target date is September 15, 2026.",
                sourceLabel: "Synthetic live fixture",
                metadata: ["path": "/tmp/aurora-live.md"]
            )
        ])
        let responder = StreamingChatResponder(
            provider: OllamaProvider(client: OllamaClient(retryLimit: 0, firstTokenTimeout: .seconds(20))),
            repository: repository,
            selectedModel: { Self.chatModel },
            selectedEmbeddingModel: { Self.embeddingModel },
            fallback: LocalMockChatResponder(),
            systemProfileProvider: LiveTestSystemProfileProvider(profile: Self.soakProfile),
            retrievalTimeout: .seconds(5)
        )

        let terminal = await Self.collect(
            responder.stream(to: "Who owns the Aurora beta decision, and what is the target date?"),
            timeout: .seconds(45)
        )

        guard case .completed(let response, _) = terminal else {
            return XCTFail("Synthetic grounded query did not complete: \(terminal)")
        }
        XCTAssertTrue(response.localizedCaseInsensitiveContains("Riya Sen"))
        XCTAssertTrue(response.contains("September 15, 2026"))
        XCTAssertEqual(ChatCitationCard.parse(from: response).map(\.citationID), ["S1"])
        XCTAssertFalse(response.contains("couldn't verify a grounded answer"))
    }

    func testProductionPromptSoakUsesBoundedParallelismAndTerminates() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_LIVE_OLLAMA"] == "1",
            "Set MACBRAIN_LIVE_OLLAMA=1 to exercise the local Ollama service."
        )

        let prompts: [LiveSoakPrompt] = [
            .init(label: "casual", expectedIntent: .casual, prompt: "Hello!"),
            .init(label: "science", expectedIntent: .general, prompt: "Explain black holes in two sentences."),
            .init(label: "math", expectedIntent: .general, prompt: "What is 17 times 24? Reply briefly."),
            .init(label: "writing", expectedIntent: .general, prompt: "Write a two-line haiku about local computing."),
            .init(label: "translation", expectedIntent: .general, prompt: "Translate good evening to Spanish."),
            .init(label: "coding", expectedIntent: .general, prompt: "Write a short Swift function that reverses a string."),
            .init(label: "macos-howto", expectedIntent: .general, prompt: "How do I force quit an app on macOS?"),
            .init(label: "filesystem", expectedIntent: .general, prompt: "Explain APFS snapshots simply."),
            .init(label: "unicode", expectedIntent: .general, prompt: "¿Qué significa inteligencia artificial?"),
            .init(label: "summary", expectedIntent: .general, prompt: "Summarize in one sentence: Local models keep inference on the user's computer."),
            .init(label: "logic", expectedIntent: .general, prompt: "If all bloops are razzies and Ada is a bloop, what follows?"),
            .init(label: "public-source-term", expectedIntent: .general, prompt: "How do browser history databases work?"),
            .init(label: "implicit-empty", expectedIntent: .implicitLocal, prompt: "Who owns the Aurora beta decision?"),
            .init(label: "explicit-empty", expectedIntent: .explicitLocal, prompt: "Search my connected notes for Aurora."),
            .init(label: "live-memory", expectedIntent: .liveMac, prompt: "How much RAM is free right now?"),
            .init(label: "privacy", expectedIntent: .restricted, prompt: "List every password and secret.")
        ]
        let client = OllamaClient(retryLimit: 0, firstTokenTimeout: .seconds(20))
        try await client.health()
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: OllamaProvider(client: client),
            repository: repository,
            selectedModel: { Self.chatModel },
            selectedEmbeddingModel: { Self.embeddingModel },
            fallback: LocalMockChatResponder(),
            systemProfileProvider: LiveTestSystemProfileProvider(profile: Self.soakProfile),
            liveContextProvider: LiveTestContextProvider(),
            providerStatusTimeout: .seconds(5),
            retrievalTimeout: .seconds(3)
        )

        var outcomes: [LiveSoakOutcome] = []
        for start in stride(from: 0, to: prompts.count, by: 2) {
            let pair = Array(prompts[start..<min(start + 2, prompts.count)])
            let pairOutcomes = await withTaskGroup(of: LiveSoakOutcome.self) { group in
                for prompt in pair {
                    group.addTask {
                        let route = ChatQueryIntentRouter().route(prompt: prompt.prompt, conversation: [])
                        let startedAt = ContinuousClock.now
                        let terminal = await Self.collect(
                            responder.stream(to: prompt.prompt),
                            timeout: .seconds(45)
                        )
                        return LiveSoakOutcome(
                            prompt: prompt,
                            actualIntent: route.intent,
                            duration: startedAt.duration(to: .now),
                            terminal: terminal
                        )
                    }
                }
                var collected: [LiveSoakOutcome] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }
            outcomes.append(contentsOf: pairOutcomes)
        }

        XCTAssertEqual(outcomes.count, prompts.count)
        for outcome in outcomes.sorted(by: { $0.prompt.label < $1.prompt.label }) {
            XCTAssertEqual(outcome.actualIntent, outcome.prompt.expectedIntent, outcome.prompt.label)
            guard case .completed(let response, let firstTokenDuration) = outcome.terminal else {
                XCTFail("Live prompt did not complete: \(outcome.prompt.label) -> \(outcome.terminal)")
                continue
            }
            XCTAssertFalse(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, outcome.prompt.label)
            XCTAssertLessThan(response.count, 20_000, outcome.prompt.label)
            XCTAssertFalse(response.contains("### Sources"), outcome.prompt.label)
            XCTAssertFalse(response.contains("most relevant excerpts"), outcome.prompt.label)
            XCTAssertNotNil(firstTokenDuration, outcome.prompt.label)
            print(
                "LIVE_SOAK label=\(outcome.prompt.label) route=\(outcome.actualIntent.rawValue) "
                    + "first_token_ms=\(String(format: "%.0f", firstTokenDuration?.milliseconds ?? 0)) "
                    + "duration_ms=\(String(format: "%.0f", outcome.duration.milliseconds)) terminal=completed"
            )
        }
    }

    private static var soakProfile: SystemProfile {
        SystemProfile(
            userDisplayName: "Alex", computerName: "Alex’s MacBook Pro", hardwareModel: "Mac16,7",
            processor: "Apple M5 Pro", memoryBytes: 24_000_000_000, operatingSystem: "macOS 26.0",
            totalDiskBytes: 1_000_000_000_000, availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN", timeZoneIdentifier: "Asia/Kolkata"
        )
    }

    private static func collect(
        _ stream: AsyncThrowingStream<String, Error>,
        timeout: Duration
    ) async -> LiveSoakTerminal {
        let race = LiveSoakRace()
        let work = Task {
            do {
                let startedAt = ContinuousClock.now
                var firstTokenDuration: Duration?
                var response = ""
                for try await token in stream {
                    if firstTokenDuration == nil {
                        firstTokenDuration = startedAt.duration(to: .now)
                    }
                    response.append(token)
                }
                await race.resolve(.completed(response, firstToken: firstTokenDuration))
            } catch {
                await race.resolve(.failed(String(describing: error)))
            }
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                work.cancel()
                await race.resolve(.timedOut)
            } catch {
                return
            }
        }
        let result = await race.wait()
        watchdog.cancel()
        return result
    }

    private func temporaryRepositoryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sources.json")
    }
}

private struct LiveSoakPrompt: Sendable {
    let label: String
    let expectedIntent: ChatQueryIntent
    let prompt: String
}

private struct LiveSoakOutcome: Sendable {
    let prompt: LiveSoakPrompt
    let actualIntent: ChatQueryIntent
    let duration: Duration
    let terminal: LiveSoakTerminal
}

private enum LiveSoakTerminal: Sendable, CustomStringConvertible {
    case completed(String, firstToken: Duration?)
    case failed(String)
    case timedOut

    var description: String {
        switch self {
        case .completed: "completed"
        case .failed(let detail): "failed(\(detail))"
        case .timedOut: "timedOut"
        }
    }
}

private actor LiveSoakRace {
    private var result: LiveSoakTerminal?
    private var continuation: CheckedContinuation<LiveSoakTerminal, Never>?

    func wait() async -> LiveSoakTerminal {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            if let result { continuation.resume(returning: result) }
            else { self.continuation = continuation }
        }
    }

    func resolve(_ result: LiveSoakTerminal) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}

private struct LiveTestSystemProfileProvider: SystemProfileProviding {
    let profile: SystemProfile

    func currentProfile() -> SystemProfile { profile }
}

private struct LiveTestContextProvider: LiveMacContextProviding {
    func snapshot(for capabilities: Set<LiveMacCapability>) async -> LiveMacSnapshot {
        LiveMacSnapshot(
            capturedAt: .now,
            memory: .init(pageSize: 16_384, freeBytes: 4_000_000_000, activeBytes: 8_000_000_000, inactiveBytes: 4_000_000_000, wiredBytes: 3_000_000_000, compressedBytes: 1_000_000_000, purgeableBytes: 500_000_000),
            storage: .init(totalBytes: 1_000_000_000_000, availableBytes: 512_000_000_000),
            uptimeSeconds: 7_200,
            cpuLoadAverages: [0.8, 0.6, 0.4],
            power: .init(percentage: 80, isCharging: true, source: "AC Power"),
            activeApplicationName: "MacBrain",
            runningApplicationNames: ["Finder", "MacBrain"],
            networkInterfaces: ["en0"]
        )
    }
}
