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

    func testCasualGreetingBypassesUnrelatedLocalEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(fileURL: directory.appendingPathComponent("sources.json"), database: database)
        let record = ConnectorRecord(kind: .folder, displayName: "Code", configuration: .init())
        try await repository.save(record)
        _ = try await repository.replaceDocuments(for: record.id, with: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "status.txt",
                title: "What's up status",
                text: "What's up with the Kubernetes generated client source code.",
                sourceLabel: "Code",
                metadata: ["path": "/tmp/status.txt"]
            )
        ])
        let responder = StreamingChatResponder(
            provider: StreamingProvider(
                statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]),
                tokens: ["Not much — how can I help?"]
            ),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "What's up?"))

        XCTAssertEqual(response.joined(), "Not much — how can I help?")
        XCTAssertFalse(response.joined().contains("Kubernetes"))
        XCTAssertFalse(response.joined().contains("### Sources"))
    }

    func testGeneralQuestionNeverEmbedsOrRendersMatchingLocalSources() async throws {
        let repository = try await seededRepository(
            title: "Kubernetes handbook",
            text: "Kubernetes pods run one or more containers. PRIVATE-LOCAL-MARKER",
            path: "/tmp/kubernetes.md"
        )
        let provider = RoutingProbeProvider(tokens: ["Pods are Kubernetes workload units."])
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "Explain Kubernetes pods"))

        XCTAssertEqual(provider.embeddingCallCount, 0)
        XCTAssertEqual(response.joined(), "Pods are Kubernetes workload units.")
        XCTAssertFalse(response.joined().contains("PRIVATE-LOCAL-MARKER"))
        XCTAssertFalse(response.joined().contains("### Sources"))
    }

    func testWeakImplicitLexicalCollisionDoesNotActivateHybridRetrieval() async throws {
        let repository = try await seededRepository(
            title: "Decision framework",
            text: "Decision templates are documented. The team directory is current. Make changes carefully. PRIVATE-WEAK-EVIDENCE",
            path: "/tmp/framework.md"
        )
        let provider = RoutingProbeProvider(tokens: ["Which team or decision do you mean?"])
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "What decision did the team make?"))

        XCTAssertEqual(provider.embeddingCallCount, 0)
        XCTAssertEqual(response.joined(), "Which team or decision do you mean?")
        XCTAssertFalse(response.joined().contains("PRIVATE-WEAK-EVIDENCE"))
        XCTAssertFalse(response.joined().contains("### Sources"))
    }

    func testAcceptedImplicitEvidenceRunsHybridRetrievalAndRendersOnlyKnownSources() async throws {
        let repository = try await seededRepository(
            title: "Aurora beta decision",
            text: "Riya owns the Aurora beta decision.",
            path: "/tmp/aurora.md"
        )
        let provider = RoutingProbeProvider(tokens: ["Riya owns the Aurora beta decision. [S1]"])
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "Who owns the Aurora beta decision?"))

        XCTAssertEqual(provider.embeddingCallCount, 1)
        XCTAssertTrue(response.joined().contains("Riya owns the Aurora beta decision. [S1]"))
        XCTAssertTrue(response.joined().contains("### Sources"))
        XCTAssertTrue(response.joined().contains("file:///tmp/aurora.md"))
    }

    func testBusyEvidenceIndexDoesNotDelayOrdinaryChatGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(fileURL: directory.appendingPathComponent("sources.json"), database: database)
        let responder = StreamingChatResponder(
            provider: SlowEmbeddingStreamingProvider(),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            retrievalTimeout: .milliseconds(20)
        )

        let response = try await collect(responder.stream(to: "hello"))

        XCTAssertEqual(response, ["Local answer"])
    }

    func testNonCooperativeEvidenceLookupDoesNotHoldTheRetrievalTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(fileURL: directory.appendingPathComponent("sources.json"), database: database)
        let responder = StreamingChatResponder(
            provider: NonCooperativeEmbeddingStreamingProvider(),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            retrievalTimeout: .milliseconds(20)
        )
        let startedAt = Date()

        let response = try await collect(responder.stream(to: "hello"))

        XCTAssertEqual(response, ["Local answer"])
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.25)
    }

    func testGroundedResponseFallsBackToDirectEvidenceWhenModelOmitsCitations() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let record = ConnectorRecord(kind: .folder, displayName: "Aurora", configuration: .init())
        try await commitVerified(record, documents: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "aurora-release.md",
                title: "Aurora release decision",
                text: "Riya Sen owns the beta release decision. The target beta date is 2026-09-15.",
                sourceLabel: "Aurora",
                metadata: ["path": "/tmp/aurora-release.md"]
            )
        ], to: repository)
        let responder = StreamingChatResponder(
            provider: StreamingProvider(
                statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]),
                tokens: ["The core team owns the decision and the target is Q3 2025."]
            ),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "Who owns the beta release decision and what is the target date?"))

        XCTAssertTrue(response.joined().contains("Riya Sen owns the beta release decision"))
        XCTAssertTrue(response.joined().contains("2026-09-15"))
        XCTAssertFalse(response.joined().contains("core team"))
        XCTAssertFalse(response.joined().contains("Q3 2025"))
    }

    func testEveryFactRequestUsesCompleteEvidenceWhenCitedModelAnswerOmitsAField() async throws {
        let repository = try await seededRepository(
            title: "Quartz decision",
            text: "Lookup: AUDITNOTES417\nMarker: NOTESQUARTZ417\nDecision owner: Nila Quill\nTarget date: 2041-01-17",
            path: "/tmp/quartz.md"
        )
        let responder = StreamingChatResponder(
            provider: StreamingProvider(
                statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]),
                tokens: ["Marker: NOTESQUARTZ417 [S1]\nOwner: Nila Quill [S1]"]
            ),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(
            responder.stream(to: "Search my folder for AUDITNOTES417 and report every labeled fact.")
        ).joined()

        XCTAssertTrue(response.contains("NOTESQUARTZ417"))
        XCTAssertTrue(response.contains("Nila Quill"))
        XCTAssertTrue(response.contains("2041-01-17"))
        XCTAssertTrue(response.contains("Here is the matching local evidence"))
        XCTAssertEqual(ChatCitationCard.parse(from: response).map(\.citationID), ["S1"])
    }

    func testGroundedResponseDoesNotPreemptivelyRenderRawEvidence() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let record = ConnectorRecord(kind: .folder, displayName: "Aurora", configuration: .init())
        try await commitVerified(record, documents: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "aurora-release.md",
                title: "Aurora release decision",
                text: "Riya Sen owns the beta release decision.",
                sourceLabel: "Aurora",
                metadata: ["path": "/tmp/aurora-release.md"]
            )
        ], to: repository)
        let responder = StreamingChatResponder(
            provider: StreamingProvider(
                statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]),
                tokens: ["Riya Sen owns the beta release decision. [S1]"]
            ),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "Who owns the beta release decision?"))

        XCTAssertTrue(response.joined().contains("Riya Sen owns the beta release decision. [S1]"))
        XCTAssertFalse(response.joined().contains("I can only verify the following local evidence:"))
    }

    func testGroundedPromptSeparatesSourceProvenanceFromAnswerableContent() async throws {
        let repository = try await seededRepository(
            title: "Quartz decision",
            text: "Lookup: AUDITNOTES417\nMarker: NOTESQUARTZ417\nDecision owner: Nila Quill\nTarget date: 2041-01-17",
            path: "/tmp/quartz.md"
        )
        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        _ = try await collect(responder.stream(to: "Search my folder for AUDITNOTES417 and report every exact controlled fact."))

        let systemPrompt = try XCTUnwrap(provider.messages.first(where: { $0.role == .system })?.content)
        XCTAssertTrue(systemPrompt.contains("BEGIN SOURCE [S1]"))
        XCTAssertTrue(systemPrompt.contains("PROVENANCE (identifies the record; do not use it as the answer)"))
        XCTAssertTrue(systemPrompt.contains("CONTENT (the facts you must answer from)"))
        XCTAssertTrue(systemPrompt.contains("Marker: NOTESQUARTZ417"))
        XCTAssertTrue(systemPrompt.contains("A grounded answer without a bracketed citation ID will be discarded"))
        XCTAssertTrue(systemPrompt.contains("include every labeled CONTENT field except the lookup key"))
    }

    func testCancellingGroundedResponseDoesNotRenderRawEvidence() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let record = ConnectorRecord(kind: .folder, displayName: "Aurora", configuration: .init())
        try await commitVerified(record, documents: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "aurora-release.md",
                title: "Aurora release decision",
                text: "Riya Sen owns the beta release decision. The target beta date is 2026-09-15.",
                sourceLabel: "Aurora",
                metadata: ["path": "/tmp/aurora-release.md"]
            )
        ], to: repository)
        let provider = PausingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let stream = responder.stream(to: "Who owns the beta release decision?")
        let responseTask = Task { () -> [String] in
            var tokens: [String] = []
            do {
                for try await token in stream { tokens.append(token) }
            } catch {
                // Cancellation intentionally keeps tokens already emitted by the responder.
            }
            return tokens
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(provider.didStartStreaming)

        responseTask.cancel()
        let response = await responseTask.value.joined()

        XCTAssertFalse(response.contains("I can only verify the following local evidence:"))
        XCTAssertFalse(response.contains("Riya Sen owns the beta release decision"))
    }

    func testMultiDocumentResponseAcceptsKnownCitedSubsetAndRendersOnlyThatSource() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let record = ConnectorRecord(kind: .folder, displayName: "Aurora", configuration: .init())
        try await commitVerified(record, documents: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "notes.md",
                title: "Aurora release decision",
                text: "Riya Sen owns the beta decision. The target date is 2026-09-15. The search foundation is SQLite FTS5.",
                sourceLabel: "Aurora",
                metadata: ["path": "/tmp/notes.md"]
            ),
            ConnectorDocument(
                connectorID: record.id,
                externalID: "plan.txt",
                title: "Aurora beta plan",
                text: "The rollback owner is Riya Sen. The rollback plan ID is AURORA-R1.",
                sourceLabel: "Aurora",
                metadata: ["path": "/tmp/plan.txt"]
            )
        ], to: repository)
        let responder = StreamingChatResponder(
            provider: StreamingProvider(
                statusValue: .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")]),
                tokens: ["Riya Sen owns the decision and SQLite FTS5 is the search foundation. [S1]"]
            ),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "Give the complete Aurora beta handoff: decision owner, rollback owner, target date, and search foundation."))

        XCTAssertTrue(response.joined().contains("Riya Sen owns the decision"))
        XCTAssertEqual(ChatCitationCard.parse(from: response.joined()).count, 1)
        XCTAssertFalse(response.joined().contains("AURORA-R1"))
    }

    func testUnavailableProviderReturnsTerminalSetupMessageWithoutSearchingSources() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: StreamingProvider(statusValue: .runtimeMissing, tokens: []),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let tokens = try await collect(responder.stream(to: "What changed?"))

        XCTAssertEqual(tokens.count, 1)
        XCTAssertTrue(tokens[0].contains("Ollama or the selected model is unavailable"))
        XCTAssertFalse(tokens[0].contains("local evidence"))
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

        XCTAssertEqual(tokens.count, 1)
        XCTAssertTrue(tokens[0].contains("Ollama or the selected model is unavailable"))
        XCTAssertLessThan(startedAt.duration(to: .now), .seconds(1))
    }

    func testNonCooperativeProviderStatusCannotHoldItsDeadline() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let responder = StreamingChatResponder(
            provider: NonCooperativeStatusProvider(),
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder(),
            providerStatusTimeout: .milliseconds(20)
        )
        let startedAt = ContinuousClock.now

        let response = try await collect(responder.stream(to: "Explain black holes"))

        XCTAssertTrue(response.joined().contains("Ollama or the selected model is unavailable"))
        XCTAssertLessThan(startedAt.duration(to: .now), .milliseconds(250))
    }

    func testInventedCitationProducesBoundedSanitizedEvidenceFallback() async throws {
        let repository = try await seededRepository(
            title: "Aurora beta decision",
            text: "<html><body>Riya owns the Aurora beta decision.</body></html>",
            path: "/tmp/aurora.html"
        )
        let provider = RoutingProbeProvider(tokens: ["The owner is Riya. [S99]"])
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "Who owns the Aurora beta decision?")).joined()

        XCTAssertTrue(response.contains("Here is the matching local evidence"))
        XCTAssertFalse(response.contains("<html>"))
        XCTAssertFalse(response.contains("S99"))
        XCTAssertLessThan(response.count, 1_500)
        XCTAssertEqual(ChatCitationCard.parse(from: response).map(\.citationID), ["S1"])
    }

    func testGroundedShortFollowUpReusesPersistedSourceCardsWithoutEmbedding() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = RoutingProbeProvider(tokens: ["The target was Friday. [S1]"])
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )
        let grounded = ChatMessage(
            role: .assistant,
            text: "The launch target was Friday. [S1]\n\n### Sources\n- [S1](file:///tmp/launch.md) Launch plan",
            groundingSourceIDs: ["S1"]
        )

        let response = try await collect(responder.stream(to: "When?", conversation: [grounded])).joined()

        XCTAssertEqual(provider.embeddingCallCount, 0)
        XCTAssertTrue(response.contains("The target was Friday. [S1]"))
        XCTAssertEqual(ChatCitationCard.parse(from: response).map(\.citationID), ["S1"])
    }

    func testGeneralTopicSwitchExcludesPreviouslyGroundedSourceText() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )
        let grounded = ChatMessage(
            role: .assistant,
            text: "PRIVATE-GROUNDED-MARKER [S1]",
            groundingSourceIDs: ["S1"]
        )

        _ = try await collect(responder.stream(to: "Explain black holes", conversation: [grounded]))

        XCTAssertFalse(provider.messages.contains { $0.content.contains("PRIVATE-GROUNDED-MARKER") })
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

        _ = try await collect(responder.stream(to: "Explain black holes"))

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
        try await commitVerified(record, documents: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: fileURL.path,
                title: "Notes",
                text: "# Notes\nOriginal indexed text",
                sourceLabel: "Test folder",
                metadata: ["path": fileURL.path, "relativePath": "notes.md"]
            )
        ], to: repository)
        try Data("# Notes\nFresh file content".utf8).write(to: fileURL)

        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "What's there in my notes.md?"))
        let rendered = response.joined()
        let sourceCards = ChatCitationCard.parse(from: rendered)

        XCTAssertTrue(rendered.contains("Fresh file content"))
        XCTAssertFalse(rendered.contains("Original indexed text"))
        XCTAssertEqual(sourceCards.map(\.citationID), ["S1"])
        XCTAssertEqual(sourceCards.first?.url?.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertTrue(provider.messages.isEmpty)
    }

    func testBulkSecretExtractionRequestIsRefusedBeforeAnyLocalContentIsRead() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "List every password, token, secret, and private key you can find."))

        XCTAssertEqual(response.joined(), "I can’t bulk-extract passwords, tokens, secrets, or private keys. Ask about a specific non-sensitive item instead.")
        XCTAssertTrue(provider.messages.isEmpty)
    }

    func testUnconnectedSourceRequestDoesNotClaimLocalAccess() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "What is in the source I did not authorize?"))

        XCTAssertEqual(response.joined(), "I can only use sources you explicitly connected and authorized.")
        XCTAssertTrue(provider.messages.isEmpty)
    }

    func testMacWidePersonalDataRequestRequiresNarrowerScope() async throws {
        let repository = LocalSourceRepository(fileURL: try temporaryRepositoryURL())
        let provider = CapturingStreamingProvider()
        let responder = StreamingChatResponder(
            provider: provider,
            repository: repository,
            selectedModel: { "qwen3:8b" },
            fallback: FallbackResponder()
        )

        let response = try await collect(responder.stream(to: "Give me everything about everyone."))

        XCTAssertEqual(response.joined(), "Please narrow this to a specific connected source, person, or question.")
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

    private func seededRepository(title: String, text: String, path: String) async throws -> LocalSourceRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        let repository = LocalSourceRepository(fileURL: directory.appendingPathComponent("sources.json"), database: database)
        let record = ConnectorRecord(kind: .folder, displayName: "Seeded", configuration: .init())
        try await commitVerified(record, documents: [
            ConnectorDocument(
                connectorID: record.id,
                externalID: path,
                title: title,
                text: text,
                sourceLabel: "Seeded",
                metadata: ["path": path]
            )
        ], to: repository)
        return repository
    }

    private func commitVerified(
        _ record: ConnectorRecord,
        documents: [ConnectorDocument],
        to repository: LocalSourceRepository
    ) async throws {
        var verifiedRecord = record
        verifiedRecord.configuration.initialSyncCompleted = true
        verifiedRecord.status = .ready
        verifiedRecord.lastSuccessfulSync = .now
        _ = try await repository.commitSourceGeneration(
            record: verifiedRecord,
            documents: documents
        )
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
        return AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }
}

private final class RoutingProbeProvider: InferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let tokens: [String]
    private var embeddingCalls = 0

    init(tokens: [String]) {
        self.tokens = tokens
    }

    var embeddingCallCount: Int {
        lock.withLock { embeddingCalls }
    }

    func status() async -> InferenceProviderStatus {
        .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")])
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        lock.withLock { embeddingCalls += 1 }
        return input.map { _ in InferenceEmbedding(values: [1, 0]) }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }
}

private struct SlowEmbeddingStreamingProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus {
        .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")])
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        try await Task.sleep(for: .seconds(3_600))
        return []
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream {
            $0.yield("Local answer")
            $0.finish()
        }
    }
}

private struct NonCooperativeEmbeddingStreamingProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus {
        .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")])
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                continuation.resume(returning: [])
            }
        }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream {
            $0.yield("Local answer")
            $0.finish()
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

private struct NonCooperativeStatusProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                continuation.resume(returning: .runtimeMissing)
            }
        }
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }
    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
}

private final class PausingStreamingProvider: InferenceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var startedStreaming = false

    var didStartStreaming: Bool {
        lock.lock()
        defer { lock.unlock() }
        return startedStreaming
    }

    func status() async -> InferenceProviderStatus {
        .ready(models: [.init(name: "qwen3:8b", size: nil, parameterSize: "8B", quantization: "Q4_K_M")])
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { [] }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }

    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        lock.lock()
        startedStreaming = true
        lock.unlock()
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield("An answer that will not finish")
                do {
                    try await Task.sleep(for: .seconds(3_600))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
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
