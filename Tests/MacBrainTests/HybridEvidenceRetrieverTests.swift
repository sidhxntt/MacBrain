import XCTest
@testable import MacBrain

final class HybridEvidenceRetrieverTests: XCTestCase {
    func testHybridSearchFusesExactAndSemanticEvidenceWithCitationMetadata() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let source = StoredSource(kind: "folder", displayName: "Product")
        let lexical = try await insert(
            database, source: source,
            title: "Launch decision",
            text: "The launch checklist requires citation validation before release.",
            path: "/tmp/product/launch.md",
            vector: [1, 0]
        )
        let semantic = try await insert(
            database, source: source,
            title: "Grounding policy",
            text: "Answers must be supported by local evidence.",
            path: "/tmp/product/grounding.md",
            vector: [0, 1]
        )
        let retriever = HybridEvidenceRetriever(
            database: database,
            provider: FixedEmbeddingProvider(vector: [0, 1]),
            embeddingModel: "test-embed"
        )

        let result = try await retriever.search("citation validation", limit: 4)

        XCTAssertEqual(result.evidence.first?.chunkID, lexical.id)
        XCTAssertTrue(result.evidence.contains { $0.chunkID == semantic.id })
        XCTAssertEqual(result.evidence.first?.citationID, "S1")
        XCTAssertEqual(result.evidence.first?.sourceType, "folder")
        XCTAssertEqual(result.evidence.first?.sourcePath, "/tmp/product/launch.md")
        XCTAssertEqual(result.evidence.first?.startOffset, 0)
        XCTAssertFalse(result.isLowConfidence)
    }

    func testHybridSearchDiversifiesSourcesAndCapsContext() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let primary = StoredSource(kind: "folder", displayName: "Primary")
        let secondary = StoredSource(kind: "notes", displayName: "Secondary")
        _ = try await insert(database, source: primary, title: "One", text: String(repeating: "roadmap ", count: 80), path: "/tmp/one.md", vector: [1, 0])
        _ = try await insert(database, source: primary, title: "Two", text: String(repeating: "roadmap ", count: 80), path: "/tmp/two.md", vector: [0.9, 0.1])
        let other = try await insert(database, source: secondary, title: "Three", text: "roadmap from an independent source", path: "/tmp/three.md", vector: [0.8, 0.2])
        let retriever = HybridEvidenceRetriever(
            database: database,
            provider: FixedEmbeddingProvider(vector: [1, 0]),
            embeddingModel: "test-embed",
            configuration: .init(contextCharacterBudget: 130, maximumEvidencePerSource: 1)
        )

        let result = try await retriever.search("roadmap", limit: 5)

        XCTAssertLessThanOrEqual(result.evidence.reduce(0) { $0 + $1.excerpt.count }, 130)
        XCTAssertTrue(result.evidence.contains { $0.chunkID == other.id })
        XCTAssertEqual(Set(result.evidence.map(\.sourceTitle)).count, result.evidence.count)
    }

    func testSourceScopeConstrainsLexicalSemanticAndGraphCandidates() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let allowedSource = StoredSource(kind: SourceConnectorKind.appleMail.rawValue, displayName: "Allowed Mail")
        let blockedSource = StoredSource(kind: SourceConnectorKind.appleNotes.rawValue, displayName: "Blocked Notes")
        let allowedChunk = try await insert(
            database,
            source: allowedSource,
            title: "Allowed ORBIT record",
            text: "ORBIT MAIL-SCOPE-ALLOWED-731",
            path: "/tmp/allowed-orbit.txt",
            vector: [0, 1]
        )
        let blockedChunk = try await insert(
            database,
            source: blockedSource,
            title: "Blocked ORBIT record",
            text: "ORBIT NOTES-SCOPE-BLOCKED-842",
            path: "/tmp/blocked-orbit.txt",
            vector: [1, 0]
        )
        let sharedEntity = GraphEntity(
            sourceID: allowedSource.id,
            type: .topic,
            name: "ORBIT",
            confidence: 1
        )
        try await database.save(graph: GraphMutation(
            entities: [sharedEntity],
            mentions: [
                GraphMention(
                    entityID: sharedEntity.id,
                    provenanceChunkID: allowedChunk.id,
                    startOffset: 0,
                    endOffset: 5,
                    confidence: 1
                ),
                GraphMention(
                    entityID: sharedEntity.id,
                    provenanceChunkID: blockedChunk.id,
                    startOffset: 0,
                    endOffset: 5,
                    confidence: 1
                ),
            ]
        ))
        let retriever = HybridEvidenceRetriever(
            database: database,
            provider: FixedEmbeddingProvider(vector: [1, 0]),
            embeddingModel: "test-embed"
        )

        let result = try await retriever.search("ORBIT", sourceIDs: [allowedSource.id])
        let graph = try await database.graphRelatedChunks(
            to: [allowedChunk.id],
            limit: 10,
            sourceIDs: [allowedSource.id]
        )

        XCTAssertFalse(result.evidence.isEmpty)
        XCTAssertTrue(result.evidence.allSatisfy { $0.sourceType == allowedSource.kind })
        XCTAssertFalse(result.evidence.contains { $0.excerpt.contains("NOTES-SCOPE-BLOCKED-842") })
        XCTAssertTrue(graph.allSatisfy { $0.sourceID == allowedSource.id })
        XCTAssertFalse(graph.contains { $0.id == blockedChunk.id })
    }

    func testCitationValidatorOnlyRendersKnownCitationIDs() {
        let evidence = [
            RetrievalEvidence(citationID: "S1", chunkID: UUID(), sourceTitle: "Plan", sourceType: "folder", sourcePath: "/tmp/plan.md", sourceDate: nil, excerpt: "Supported fact", startOffset: 0, endOffset: 14, pageNumber: nil, score: 0.9)
        ]

        let rendered = CitationValidator.renderedSources(for: "Answer [S1] but not [S99].", evidence: evidence)

        XCTAssertTrue(rendered.contains("[S1]"))
        XCTAssertFalse(rendered.contains("S99"))
        XCTAssertTrue(CitationValidator.hasOnlyKnownCitationIDs(in: "Answer [S1].", evidence: evidence))
        XCTAssertFalse(CitationValidator.hasOnlyKnownCitationIDs(in: "Answer [S99].", evidence: evidence))
    }

    func testCitationValidatorEncodesSpacesInLocalFileURLs() {
        let evidence = [
            RetrievalEvidence(
                citationID: "S1",
                chunkID: UUID(),
                sourceTitle: "Project notes",
                sourceType: "folder",
                sourcePath: "/tmp/Project Notes/launch plan.md",
                sourceDate: nil,
                excerpt: "Supported fact",
                startOffset: 0,
                endOffset: 14,
                pageNumber: nil,
                score: 0.9
            )
        ]

        let rendered = CitationValidator.renderedSources(for: evidence)
        let cards = ChatCitationCard.parse(from: rendered)

        XCTAssertEqual(cards.map(\.citationID), ["S1"])
        XCTAssertEqual(cards.first?.url?.path, "/tmp/Project Notes/launch plan.md")
    }

    private func insert(_ database: MacBrainDatabase, source: StoredSource, title: String, text: String, path: String, vector: [Float]) async throws -> StoredChunk {
        try await database.save(source: source)
        let document = StoredDocument(sourceID: source.id, externalID: path, title: title, text: text, sourceLabel: source.displayName, modifiedAt: .now, metadata: ["path": path])
        let chunk = StoredChunk(documentID: document.id, sourceID: source.id, text: text, startOffset: 0, endOffset: text.utf16.count)
        try await database.replace(document: document, chunks: [chunk], embeddings: [StoredEmbedding(chunkID: chunk.id, vector: vector, indexIdentifier: "test-embed")])
        return chunk
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("retrieval.sqlite")
    }
}

private struct FixedEmbeddingProvider: InferenceProvider {
    let vector: [Float]
    func status() async -> InferenceProviderStatus { .runtimeMissing }
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { input.map { _ in .init(values: vector) } }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }
    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
}
