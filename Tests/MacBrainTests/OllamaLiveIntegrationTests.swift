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
        let documents = [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "aurora-live.md",
                title: "Aurora beta decision",
                text: "Riya Sen owns the Aurora beta decision. The target date is September 15, 2026.",
                sourceLabel: "Synthetic live fixture",
                metadata: ["path": "/tmp/aurora-live.md"]
            )
        ]
        var verifiedRecord = record
        verifiedRecord.configuration.initialSyncCompleted = true
        verifiedRecord.status = .ready
        verifiedRecord.lastSuccessfulSync = .now
        _ = try await repository.commitSourceGeneration(
            record: verifiedRecord,
            documents: documents
        )
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

    func testEveryConnectorPreservesGroundingAcrossTheLiveAdversarialMatrix() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MACBRAIN_LIVE_OLLAMA"] == "1",
            "Set MACBRAIN_LIVE_OLLAMA=1 to exercise the local Ollama service."
        )

        let client = OllamaClient(retryLimit: 0, firstTokenTimeout: .seconds(30))
        try await client.health()
        let models = try await client.models().map(\.name)
        XCTAssertTrue(models.contains(Self.chatModel), "Missing live chat model \(Self.chatModel)")
        XCTAssertTrue(models.contains(Self.embeddingModel), "Missing live embedding model \(Self.embeddingModel)")

        let variants: [ConnectorAuditDimension: Int] = [
            .facts: 2,
            .sourceType: 1,
            .citations: 2,
            .freshness: 0,
            .permissions: 0,
            .crossSourceIsolation: 1,
        ]
        let allCases = ConnectorAdversarialMatrix.fixtures.flatMap { fixture in
            ConnectorAuditDimension.allCases.map { dimension in
                LiveConnectorAuditCase(
                    id: "\(fixture.kind.rawValue).\(dimension.rawValue).live",
                    fixture: fixture,
                    dimension: dimension,
                    variant: variants[dimension] ?? 0
                )
            }
        }
        XCTAssertEqual(allCases.count, SourceConnectorKind.allCases.count * ConnectorAuditDimension.allCases.count)
        let requestedCase = ProcessInfo.processInfo.environment["MACBRAIN_LIVE_CONNECTOR_CASE"]
        let cases = requestedCase.map { requested in
            allCases.filter { $0.id == requested }
        } ?? allCases
        XCTAssertFalse(cases.isEmpty, "No live connector audit case matched \(requestedCase ?? "the requested filter")")

        var outcomes: [LiveConnectorAuditOutcome] = []
        for start in stride(from: 0, to: cases.count, by: 2) {
            let batch = Array(cases[start..<min(start + 2, cases.count)])
            let batchOutcomes = await withTaskGroup(of: LiveConnectorAuditOutcome.self) { group in
                for item in batch {
                    group.addTask { await Self.runLiveConnectorAuditCase(item) }
                }
                var collected: [LiveConnectorAuditOutcome] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }
            outcomes.append(contentsOf: batchOutcomes)
        }

        XCTAssertEqual(outcomes.count, cases.count)
        for outcome in outcomes.sorted(by: { $0.item.id < $1.item.id }) {
            XCTAssertEqual(outcome.actualIntent, .explicitLocal, outcome.item.id)
            guard case .completed(let response, let firstTokenDuration) = outcome.terminal else {
                XCTFail("Live connector audit did not complete: \(outcome.item.id) -> \(outcome.terminal)")
                continue
            }
            if ProcessInfo.processInfo.environment["MACBRAIN_LIVE_CONNECTOR_LOG_RESPONSES"] == "1" {
                print("LIVE_CONNECTOR_RESPONSE case=\(outcome.item.id)\n\(response)\nEND_LIVE_CONNECTOR_RESPONSE")
            }

            let fixture = outcome.item.fixture
            if outcome.item.dimension == .permissions {
                for marker in [fixture.currentMarker, fixture.staleMarker, fixture.freshMarker, fixture.decoyMarker] {
                    XCTAssertFalse(response.contains(marker), "\(outcome.item.id) disclosed \(marker)")
                }
                XCTAssertTrue(ChatCitationCard.parse(from: response).isEmpty, "\(outcome.item.id) cited revoked evidence")
            } else {
                switch outcome.item.dimension {
                case .facts:
                    for fact in fixture.expectedFacts {
                        XCTAssertTrue(response.contains(fact), "\(outcome.item.id) omitted \(fact)")
                    }
                case .citations, .freshness, .crossSourceIsolation:
                    XCTAssertTrue(response.contains(outcome.expectedMarker), "\(outcome.item.id) omitted \(outcome.expectedMarker)")
                case .sourceType, .permissions:
                    break
                }
                for marker in outcome.forbiddenMarkers {
                    XCTAssertFalse(response.contains(marker), "\(outcome.item.id) leaked \(marker)")
                }
                let cards = ChatCitationCard.parse(from: response)
                XCTAssertEqual(cards.count, 1, "\(outcome.item.id) rendered the wrong citation count")
                if let card = cards.first {
                    XCTAssertEqual(card.citationID, "S1", outcome.item.id)
                    XCTAssertEqual(card.sourceType, fixture.kind.rawValue, outcome.item.id)
                    XCTAssertTrue(card.title.contains(fixture.title), outcome.item.id)
                    XCTAssertEqual(card.url, outcome.expectedURL, outcome.item.id)
                }
                XCTAssertFalse(response.contains("couldn't verify a grounded answer"), outcome.item.id)
            }

            let answerPath: String
            if outcome.item.dimension == .permissions {
                answerPath = "permission-state"
            } else if response.hasPrefix("Here is the matching local evidence:") {
                answerPath = "verified-evidence-fallback"
            } else {
                answerPath = "model"
            }

            print(
                "LIVE_CONNECTOR_AUDIT case=\(outcome.item.id) route=\(outcome.actualIntent.rawValue) "
                    + "answer_path=\(answerPath) "
                    + "first_token_ms=\(String(format: "%.0f", firstTokenDuration?.milliseconds ?? 0)) "
                    + "duration_ms=\(String(format: "%.0f", outcome.duration.milliseconds)) terminal=completed"
            )
        }
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

    fileprivate static var soakProfile: SystemProfile {
        SystemProfile(
            userDisplayName: "Alex", computerName: "Alex’s MacBook Pro", hardwareModel: "Mac16,7",
            processor: "Apple M5 Pro", memoryBytes: 24_000_000_000, operatingSystem: "macOS 26.0",
            totalDiskBytes: 1_000_000_000_000, availableDiskBytes: 512_000_000_000,
            localeIdentifier: "en_IN", timeZoneIdentifier: "Asia/Kolkata"
        )
    }

    private static func runLiveConnectorAuditCase(
        _ item: LiveConnectorAuditCase
    ) async -> LiveConnectorAuditOutcome {
        let startedAt = ContinuousClock.now
        do {
            let environment = try LiveConnectorAuditEnvironment()
            defer { environment.removeTemporaryFiles() }
            let fixture = item.fixture
            let decoy = ConnectorAdversarialMatrix.decoy(for: fixture.kind)
            var expectedMarker = fixture.currentMarker
            var forbiddenMarkers = [fixture.staleMarker, fixture.freshMarker, fixture.decoyMarker]

            switch item.dimension {
            case .facts, .sourceType, .citations, .crossSourceIsolation:
                _ = try await environment.seed(fixture, marker: fixture.currentMarker)
                _ = try await environment.seed(
                    decoy,
                    marker: fixture.decoyMarker,
                    lookupToken: fixture.lookupToken
                )
            case .freshness:
                let record = try await environment.seed(fixture, marker: fixture.staleMarker)
                _ = try await environment.seed(
                    decoy,
                    marker: fixture.decoyMarker,
                    lookupToken: fixture.lookupToken
                )
                _ = try await environment.replace(fixture, record: record, marker: fixture.freshMarker)
                expectedMarker = fixture.freshMarker
                forbiddenMarkers = [fixture.staleMarker, fixture.currentMarker, fixture.decoyMarker]
            case .permissions:
                _ = try await environment.seed(
                    decoy,
                    marker: fixture.decoyMarker,
                    lookupToken: fixture.lookupToken
                )
                var record = try await environment.seed(fixture, marker: fixture.currentMarker)
                record.status = .needsAuthorization
                record.lastError = "Controlled live permission denial"
                try await environment.repository.save(record)
            }

            let prompt = item.prompt
            let intent = ChatQueryIntentRouter().route(prompt: prompt, conversation: []).intent
            let terminal = await collect(
                environment.responder(
                    chatModel: chatModel,
                    embeddingModel: embeddingModel
                ).stream(to: prompt),
                timeout: .seconds(60)
            )
            return LiveConnectorAuditOutcome(
                item: item,
                actualIntent: intent,
                duration: startedAt.duration(to: .now),
                terminal: terminal,
                expectedMarker: expectedMarker,
                forbiddenMarkers: forbiddenMarkers,
                expectedURL: fixture.expectedURL(in: environment.directory)
            )
        } catch {
            return LiveConnectorAuditOutcome(
                item: item,
                actualIntent: .general,
                duration: startedAt.duration(to: .now),
                terminal: .failed(String(describing: error)),
                expectedMarker: item.fixture.currentMarker,
                forbiddenMarkers: [],
                expectedURL: nil
            )
        }
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

private struct LiveConnectorAuditCase: Sendable {
    let id: String
    let fixture: ConnectorAdversarialFixture
    let dimension: ConnectorAuditDimension
    let variant: Int

    var prompt: String {
        let source = fixture.sourceReferences[variant]
        switch dimension {
        case .facts:
            return "Search \(source) for \(fixture.lookupToken). Report every labeled fact in that record except the lookup key, including the Marker, and preserve every value exactly."
        case .sourceType:
            return "Search \(source) for \(fixture.lookupToken). Identify the exact record and connector source type."
        case .citations:
            return "What exact Marker is recorded for \(fixture.lookupToken) in \(source)? Cite the record that proves it."
        case .freshness:
            return "Check \(source) now. What is the current Marker value for \(fixture.lookupToken)? Do not reuse an earlier value."
        case .permissions:
            return fixture.prompt(for: dimension, variant: variant)
        case .crossSourceIsolation:
            return "Using only \(source), what Marker is recorded for \(fixture.lookupToken)? Ignore same-token records in every other connector."
        }
    }
}

private struct LiveConnectorAuditOutcome: Sendable {
    let item: LiveConnectorAuditCase
    let actualIntent: ChatQueryIntent
    let duration: Duration
    let terminal: LiveSoakTerminal
    let expectedMarker: String
    let forbiddenMarkers: [String]
    let expectedURL: URL?
}

private struct LiveConnectorAuditEnvironment {
    let directory: URL
    let repository: LocalSourceRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBrainLiveConnectorAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
    }

    func seed(
        _ fixture: ConnectorAdversarialFixture,
        marker: String,
        lookupToken: String? = nil
    ) async throws -> ConnectorRecord {
        let record = ConnectorRecord(
            kind: fixture.kind,
            displayName: fixture.displayName,
            configuration: .init()
        )
        try await repository.save(record)
        return try await replace(fixture, record: record, marker: marker, lookupToken: lookupToken)
    }

    func replace(
        _ fixture: ConnectorAdversarialFixture,
        record: ConnectorRecord,
        marker: String,
        lookupToken: String? = nil
    ) async throws -> ConnectorRecord {
        let document = fixture.document(
            connectorID: record.id,
            marker: marker,
            lookupToken: lookupToken,
            rootDirectory: directory
        )
        if let url = fixture.expectedURL(in: directory), url.isFileURL {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(document.text.utf8).write(to: url, options: .atomic)
        }
        var verifiedRecord = record
        verifiedRecord.configuration.initialSyncCompleted = true
        verifiedRecord.status = .ready
        verifiedRecord.lastSuccessfulSync = .now
        _ = try await repository.commitSourceGeneration(
            record: verifiedRecord,
            documents: [document]
        )
        return verifiedRecord
    }

    func responder(chatModel: String, embeddingModel: String) -> StreamingChatResponder {
        StreamingChatResponder(
            provider: OllamaProvider(client: OllamaClient(retryLimit: 0, firstTokenTimeout: .seconds(30))),
            repository: repository,
            selectedModel: { chatModel },
            selectedEmbeddingModel: { embeddingModel },
            fallback: LocalMockChatResponder(),
            systemProfileProvider: LiveTestSystemProfileProvider(profile: OllamaLiveIntegrationTests.soakProfile),
            providerStatusTimeout: .seconds(5),
            retrievalTimeout: .seconds(10)
        )
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
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
