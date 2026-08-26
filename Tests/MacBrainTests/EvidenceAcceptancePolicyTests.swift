import XCTest
@testable import MacBrain

final class EvidenceAcceptancePolicyTests: XCTestCase {
    func testImplicitLocalRequiresAbsoluteLexicalOverlap() {
        let policy = EvidenceAcceptancePolicy()

        let accepted = policy.evaluate(
            prompt: "Who owns the Aurora beta decision?",
            intent: .implicitLocal,
            lexical: result(title: "Aurora beta handoff", excerpt: "Riya owns the Aurora beta rollout decision.")
        )
        let rejected = policy.evaluate(
            prompt: "Who owns the Aurora beta decision?",
            intent: .implicitLocal,
            lexical: result(title: "Kubernetes client", excerpt: "Generated OpenAPI configuration and UTF-8 encoding helpers.", score: 99)
        )

        XCTAssertTrue(accepted.accepted)
        XCTAssertFalse(rejected.accepted)
        XCTAssertFalse(accepted.reason.isEmpty)
        XCTAssertFalse(rejected.reason.isEmpty)
    }

    func testDistinctiveInternalEntityCanPassWithoutGenericIntentWords() {
        let evaluation = EvidenceAcceptancePolicy().evaluate(
            prompt: "What is the status of NotchBrain?",
            intent: .implicitLocal,
            lexical: result(title: "Engineering update", excerpt: "NotchBrain indexing is ready for the beta.")
        )

        XCTAssertTrue(evaluation.accepted)
    }

    func testGenericSingleWordOverlapDoesNotActivateLocalEvidence() {
        let evaluation = EvidenceAcceptancePolicy().evaluate(
            prompt: "What decision did the team make?",
            intent: .implicitLocal,
            lexical: result(title: "Team directory", excerpt: "The team contact list was refreshed.")
        )

        XCTAssertFalse(evaluation.accepted)
    }

    func testExplicitLocalAcceptsAvailableEvidenceButNotEmptyResults() {
        let policy = EvidenceAcceptancePolicy()

        XCTAssertTrue(policy.evaluate(
            prompt: "Search my notes for Aurora",
            intent: .explicitLocal,
            lexical: result(title: "Notes", excerpt: "A note")
        ).accepted)
        XCTAssertFalse(policy.evaluate(
            prompt: "Search my notes for Aurora",
            intent: .explicitLocal,
            lexical: .empty
        ).accepted)
    }

    func testNonLocalIntentsNeverAcceptEvidence() {
        let evidence = result(title: "Hello", excerpt: "hello from a local file")
        for intent in [ChatQueryIntent.casual, .general, .liveMac, .restricted] {
            XCTAssertFalse(EvidenceAcceptancePolicy().evaluate(
                prompt: "hello",
                intent: intent,
                lexical: evidence
            ).accepted)
        }
    }

    func testLexicalSearchDoesNotCallEmbeddingProvider() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let source = StoredSource(kind: "folder", displayName: "Product")
        try await database.save(source: source)
        let document = StoredDocument(
            sourceID: source.id,
            externalID: "aurora.md",
            title: "Aurora handoff",
            text: "Riya owns the Aurora beta decision.",
            sourceLabel: source.displayName
        )
        let chunk = StoredChunk(
            documentID: document.id,
            sourceID: source.id,
            text: document.text,
            startOffset: 0,
            endOffset: document.text.utf16.count
        )
        try await database.replace(document: document, chunks: [chunk], embeddings: [])
        let calls = EmbeddingCallCounter()
        let retriever = HybridEvidenceRetriever(
            database: database,
            provider: CountingEmbeddingProvider(calls: calls),
            embeddingModel: "unused"
        )

        let result = try await retriever.searchLexical("Aurora beta", limit: 4)
        let embeddingCallCount = await calls.value

        XCTAssertEqual(result.evidence.first?.chunkID, chunk.id)
        XCTAssertEqual(embeddingCallCount, 0)
    }

    private func result(title: String, excerpt: String, score: Double = 0.9) -> EvidenceSearchResult {
        EvidenceSearchResult(evidence: [
            RetrievalEvidence(
                citationID: "S1",
                chunkID: UUID(),
                sourceTitle: title,
                sourceType: "folder",
                sourcePath: "/tmp/evidence.md",
                sourceDate: nil,
                excerpt: excerpt,
                startOffset: 0,
                endOffset: excerpt.utf16.count,
                pageNumber: nil,
                score: score
            )
        ], isLowConfidence: false)
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("evidence-gate.sqlite")
    }
}

private actor EmbeddingCallCounter {
    private(set) var value = 0
    func record() { value += 1 }
}

private struct CountingEmbeddingProvider: InferenceProvider {
    let calls: EmbeddingCallCounter

    func status() async -> InferenceProviderStatus { .ready(models: []) }
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] {
        await calls.record()
        return input.map { _ in InferenceEmbedding(values: [1, 0]) }
    }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
