import Foundation
import Testing
@testable import MacBrain

struct SourceAccessRetrievalTests {
    @Test("Document rows are not queryable until their connector index is verified")
    func unverifiedRowsCannotBeRetrieved() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }

        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Unverified Notes",
            configuration: .init(),
            status: .ready
        )
        try await fixture.repository.save(record)
        _ = try await fixture.repository.replaceDocuments(
            for: record.id,
            with: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "unverified-private-117",
                    title: "Unverified private note",
                    text: "UNVERIFIED-PRIVATE-117 must never escape staging.",
                    sourceLabel: "Apple Notes"
                )
            ]
        )

        let lexical = await fixture.repository.searchLexicalEvidence("UNVERIFIED-PRIVATE-117")
        let documents = await fixture.repository.search("UNVERIFIED-PRIVATE-117")

        #expect(lexical.evidence.isEmpty)
        #expect(documents.isEmpty)
    }

    @Test("Cached chunks become ineligible when connector authorization is lost")
    func revokedSourceCannotBeRetrieved() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }

        var record = ConnectorRecord(
            kind: .appleMail,
            displayName: "Controlled Mail",
            configuration: .init()
        )
        try await fixture.commitVerified(
            record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "mail-private-731",
                    title: "Controlled authorization record",
                    text: "MAILPRIVATE731 must disappear after authorization is revoked.",
                    sourceLabel: "Apple Mail"
                )
            ]
        )

        let authorized = await fixture.repository.searchLexicalEvidence("MAILPRIVATE731")
        try #require(authorized.evidence.isEmpty == false)

        record.status = .needsAuthorization
        record.lastError = "Permission revoked for the controlled test."
        try await fixture.repository.save(record)

        let revoked = await fixture.repository.searchLexicalEvidence("MAILPRIVATE731")
        #expect(revoked.evidence.isEmpty)
    }

    @Test("Revoked sources cannot trigger semantic retrieval")
    func revokedSourceDoesNotRequestEmbeddings() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }

        var record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Controlled Notes",
            configuration: .init()
        )
        try await fixture.repository.save(record)
        _ = try await fixture.repository.replaceDocuments(
            for: record.id,
            with: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "note-private-842",
                    title: "Controlled revoked note",
                    text: "NOTEPRIVATE842 is cached but no longer authorized.",
                    sourceLabel: "Apple Notes"
                )
            ]
        )
        record.status = .needsAuthorization
        try await fixture.repository.save(record)
        let provider = SourceAccessEmbeddingProvider()

        let result = await fixture.repository.searchEvidence(
            "NOTEPRIVATE842",
            using: provider,
            embeddingModel: "controlled-embedding"
        )

        #expect(result.evidence.isEmpty)
        #expect(await provider.embeddingCallCount == 0)
    }

    @Test("An explicit connector scope excludes colliding evidence from other sources")
    func namedMailScopeExcludesNotesCollision() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }

        let mail = ConnectorRecord(
            kind: .appleMail,
            displayName: "Controlled Mail",
            configuration: .init()
        )
        let notes = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Controlled Notes",
            configuration: .init()
        )
        try await fixture.commitVerified(
            mail,
            documents: [
                ConnectorDocument(
                    connectorID: mail.id,
                    externalID: "mail-orbit",
                    title: "ORBIT handoff",
                    text: "ORBIT belongs to MAIL-FACT-512.",
                    sourceLabel: "Apple Mail"
                )
            ]
        )
        try await fixture.commitVerified(
            notes,
            documents: [
                ConnectorDocument(
                    connectorID: notes.id,
                    externalID: "notes-orbit",
                    title: "ORBIT handoff",
                    text: "ORBIT belongs to NOTES-DECOY-936.",
                    sourceLabel: "Apple Notes"
                )
            ]
        )

        let result = await fixture.repository.searchLexicalEvidence(
            "Find ORBIT in my Mail",
            sourceKinds: [.appleMail]
        )

        #expect(result.evidence.isEmpty == false)
        #expect(Set(result.evidence.map(\.sourceType)) == [SourceConnectorKind.appleMail.rawValue])
        #expect(result.evidence.contains { $0.excerpt.contains("MAIL-FACT-512") })
        #expect(result.evidence.contains { $0.excerpt.contains("NOTES-DECOY-936") } == false)
    }

    @Test("Responder applies the named connector scope before model generation")
    func responderExcludesCollidingSourceFromGroundedAnswer() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }

        let mail = ConnectorRecord(kind: .appleMail, displayName: "Controlled Mail", configuration: .init())
        let notes = ConnectorRecord(kind: .appleNotes, displayName: "Controlled Notes", configuration: .init())
        try await fixture.commitVerified(
            mail,
            documents: [
                ConnectorDocument(
                    connectorID: mail.id,
                    externalID: "mail-orbit",
                    title: "ORBIT handoff",
                    text: "ORBIT belongs to MAIL-FACT-512.",
                    sourceLabel: "Apple Mail"
                )
            ]
        )
        try await fixture.commitVerified(
            notes,
            documents: [
                ConnectorDocument(
                    connectorID: notes.id,
                    externalID: "notes-orbit",
                    title: "ORBIT handoff",
                    text: "ORBIT belongs to NOTES-DECOY-936.",
                    sourceLabel: "Apple Notes"
                )
            ]
        )
        let responder = StreamingChatResponder(
            provider: SourceIsolationResponderProvider(),
            repository: fixture.repository,
            selectedModel: { "controlled-chat" },
            selectedEmbeddingModel: { "controlled-embedding" },
            fallback: SourceAccessFallbackResponder(),
            systemProfileProvider: SourceAccessSystemProfileProvider()
        )

        var response = ""
        for try await token in responder.stream(to: "Find ORBIT in my Mail") {
            response.append(token)
        }

        #expect(response.contains("MAIL-FACT-512"))
        #expect(response.contains("NOTES-DECOY-936") == false)
    }

    @Test("Generic document search filters revoked sources before applying its result limit")
    func genericSearchDoesNotLetRevokedDocumentsCrowdOutAuthorizedMatches() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }

        var revoked = ConnectorRecord(kind: .appleNotes, displayName: "Revoked Notes", configuration: .init())
        let authorized = ConnectorRecord(kind: .appleMail, displayName: "Authorized Mail", configuration: .init())
        try await fixture.commitVerified(
            revoked,
            documents: [
                ConnectorDocument(
                    connectorID: revoked.id,
                    externalID: "revoked-orion-vault",
                    title: "ORIONVAULT ORIONVAULT ORIONVAULT",
                    text: String(repeating: "ORIONVAULT ", count: 20) + "REVOKED-DOCUMENT-517",
                    sourceLabel: "Revoked Notes"
                )
            ]
        )
        try await fixture.commitVerified(
            authorized,
            documents: [
                ConnectorDocument(
                    connectorID: authorized.id,
                    externalID: "authorized-orion-vault",
                    title: "ORIONVAULT",
                    text: "ORIONVAULT AUTHORIZED-DOCUMENT-284",
                    sourceLabel: "Authorized Mail"
                )
            ]
        )
        revoked.status = .needsAuthorization
        try await fixture.repository.save(revoked)

        let matches = await fixture.repository.search("ORIONVAULT", limit: 1)

        #expect(matches.map(\.connectorID) == [authorized.id])
        #expect(matches.contains { $0.text.contains("REVOKED-DOCUMENT-517") } == false)
    }

    @Test("A revoked local-folder cache cannot be bypassed with a direct file-read prompt")
    func directFileReadHonorsRevokedAuthorization() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }
        let fileURL = fixture.directory.appendingPathComponent("private-brief.txt")
        try "DIRECT-FILE-SECRET-719".write(to: fileURL, atomically: true, encoding: .utf8)

        var record = ConnectorRecord(
            kind: .folder,
            displayName: "Controlled Folder",
            configuration: .init(localPath: fixture.directory.path)
        )
        try await fixture.commitVerified(
            record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: fileURL.path,
                    title: fileURL.lastPathComponent,
                    text: "DIRECT-FILE-SECRET-719",
                    sourceLabel: "Controlled Folder",
                    metadata: ["path": fileURL.path, "relativePath": fileURL.lastPathComponent]
                )
            ]
        )
        let tool = LocalFileReadTool(repository: fixture.repository)
        let authorized = await tool.response(for: "Read private-brief.txt")
        #expect(authorized?.contains("DIRECT-FILE-SECRET-719") == true)

        record.status = .needsAuthorization
        try await fixture.repository.save(record)
        let revoked = await tool.response(for: "Read private-brief.txt")

        #expect(revoked == nil)
    }

    @Test("Offline fallback emits typed citations and cannot quote a revoked cache")
    func localFallbackUsesEligibleTypedEvidence() async throws {
        let fixture = try SourceAccessFixture()
        defer { fixture.removeTemporaryFiles() }

        var record = ConnectorRecord(kind: .appleNotes, displayName: "Controlled Notes", configuration: .init())
        try await fixture.commitVerified(
            record,
            documents: [
                ConnectorDocument(
                    connectorID: record.id,
                    externalID: "fallback-note-394",
                    title: "Fallback authorization note",
                    text: "FALLBACK-SECRET-394 is the controlled answer.",
                    sourceLabel: "Apple Notes"
                )
            ]
        )
        let responder = LocalKnowledgeResponder(repository: fixture.repository)
        let authorized = try await responder.respond(to: "FALLBACK-SECRET-394")
        #expect(authorized.contains("FALLBACK-SECRET-394"))
        #expect(authorized.contains("- [S1] [appleNotes] Fallback authorization note"))

        record.status = .needsAuthorization
        try await fixture.repository.save(record)
        let revoked = try await responder.respond(to: "FALLBACK-SECRET-394")

        #expect(revoked.contains("FALLBACK-SECRET-394") == false)
        #expect(revoked.contains("don't have matching local source material"))
    }
}

private struct SourceAccessFixture {
    let directory: URL
    let repository: LocalSourceRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBrainSourceAccess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacBrainDatabase(url: directory.appendingPathComponent("macbrain.sqlite"))
        repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("sources.json"),
            database: database
        )
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    func commitVerified(
        _ record: ConnectorRecord,
        documents: [ConnectorDocument]
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
}

private actor SourceAccessEmbeddingProvider: InferenceProvider {
    private(set) var embeddingCallCount = 0

    func status() async -> InferenceProviderStatus { .runtimeMissing }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        embeddingCallCount += 1
        return input.map { _ in InferenceEmbedding(values: [1, 0]) }
    }

    nonisolated func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    nonisolated func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct SourceIsolationResponderProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus {
        .ready(models: [
            InferenceModel(
                name: "controlled-chat",
                size: nil,
                parameterSize: "test",
                quantization: "test"
            )
        ])
    }

    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        input.map { _ in InferenceEmbedding(values: [1, 0]) }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("MAIL-FACT-512 [S1] NOTES-DECOY-936 [S2]")
            continuation.finish()
        }
    }
}

private struct SourceAccessFallbackResponder: ChatResponder {
    func respond(to prompt: String) async throws -> String { "Controlled fallback" }
}

private struct SourceAccessSystemProfileProvider: SystemProfileProviding {
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
