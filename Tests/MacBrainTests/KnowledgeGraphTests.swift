import XCTest
@testable import MacBrain

final class KnowledgeGraphTests: XCTestCase {
    func testDeterministicExtractionCapturesRepositoryHeadingDateAndRepeatedPerson() {
        let sourceID = UUID()
        let documentID = UUID()
        let chunk = StoredChunk(documentID: documentID, sourceID: sourceID, text: "# Project: NotchBrain\nAva Patel works on NotchBrain in github.com/acme/notchbrain on 2026-08-25. Ava Patel approved the release.", startOffset: 0, endOffset: 130)

        let graph = DeterministicGraphExtractor().extract(from: [chunk])

        XCTAssertTrue(graph.entities.contains { $0.type == .project && $0.name == "NotchBrain" })
        XCTAssertTrue(graph.entities.contains { $0.type == .repository && $0.name == "acme/notchbrain" })
        XCTAssertTrue(graph.entities.contains { $0.type == .date && $0.name == "2026-08-25" })
        XCTAssertTrue(graph.entities.contains { $0.type == .person && $0.name == "Ava Patel" })
        XCTAssertTrue(graph.relationships.contains { $0.type == .worksOn })
        XCTAssertTrue(graph.mentions.allSatisfy { $0.confidence > 0 && $0.provenanceChunkID == chunk.id })
    }

    func testConflictingRelationsAndSupersedingDecisionsRemainInspectable() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let sourceID = UUID()
        try await database.save(source: StoredSource(id: sourceID, kind: "folder", displayName: "Work"))
        let document = StoredDocument(sourceID: sourceID, externalID: "decisions.md", title: "Decisions", text: "Decisions", sourceLabel: "Work")
        let chunk = StoredChunk(documentID: document.id, sourceID: sourceID, text: document.text, startOffset: 0, endOffset: 9)
        try await database.replace(document: document, chunks: [chunk], embeddings: [])
        let old = GraphEntity(sourceID: sourceID, type: .decision, name: "Use files", confidence: 0.9)
        let new = GraphEntity(sourceID: sourceID, type: .decision, name: "Use SQLite", confidence: 0.9)
        try await database.save(graph: GraphMutation(entities: [old, new], mentions: [GraphMention(entityID: new.id, provenanceChunkID: chunk.id, startOffset: 0, endOffset: 9, confidence: 0.9)], relationships: [
            GraphRelationship(fromEntityID: new.id, toEntityID: old.id, type: .supersedes, provenanceChunkID: chunk.id, confidence: 0.9),
            GraphRelationship(fromEntityID: old.id, toEntityID: new.id, type: .relatedTo, provenanceChunkID: chunk.id, confidence: 0.6)
        ]))
        let evidence = try await database.expandGraph(fromChunkIDs: [chunk.id], maximumDepth: 1, maximumResults: 4)
        XCTAssertEqual(Set(evidence.map(\.relationship.type)), [.supersedes, .relatedTo])
    }

    func testAliasResolutionDoesNotMergeLowConfidenceEntities() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let sourceID = UUID()
        try await database.save(source: StoredSource(id: sourceID, kind: "folder", displayName: "Work"))
        let entity = GraphEntity(sourceID: sourceID, type: .project, name: "NotchBrain", confidence: 0.95)
        try await database.save(graph: GraphMutation(entities: [entity], aliases: [GraphAlias(entityID: entity.id, value: "NB", confidence: 0.4)]))

        let lowConfidenceAlias = try await database.entity(matching: "NB")
        let canonicalName = try await database.entity(matching: "NotchBrain")
        XCTAssertNil(lowConfidenceAlias)
        XCTAssertEqual(canonicalName?.id, entity.id)
    }

    func testGraphCleanupAndBoundedExpansionKeepDirectSearchAvailable() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let sourceID = UUID()
        try await database.save(source: StoredSource(id: sourceID, kind: "folder", displayName: "Work"))
        let document = StoredDocument(sourceID: sourceID, externalID: "decision.md", title: "Decision", text: "Use SQLite.", sourceLabel: "Work")
        let chunk = StoredChunk(documentID: document.id, sourceID: sourceID, text: document.text, startOffset: 0, endOffset: 11)
        try await database.replace(document: document, chunks: [chunk], embeddings: [])
        let decision = GraphEntity(sourceID: sourceID, type: .decision, name: "Use SQLite", confidence: 0.9)
        let project = GraphEntity(sourceID: sourceID, type: .project, name: "NotchBrain", confidence: 0.9)
        try await database.save(graph: GraphMutation(
            entities: [decision, project],
            mentions: [GraphMention(entityID: decision.id, provenanceChunkID: chunk.id, startOffset: 0, endOffset: 11, confidence: 0.9)],
            relationships: [GraphRelationship(fromEntityID: decision.id, toEntityID: project.id, type: .belongsToProject, provenanceChunkID: chunk.id, confidence: 0.9)]
        ))

        let expanded = try await database.expandGraph(fromChunkIDs: [chunk.id], maximumDepth: 1, maximumResults: 1)
        XCTAssertEqual(expanded.count, 1)
        try await database.remove(chunkID: chunk.id)
        let remaining = try await database.expandGraph(fromChunkIDs: [chunk.id], maximumDepth: 2, maximumResults: 5)
        XCTAssertTrue(remaining.isEmpty)
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KnowledgeGraphTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("macbrain.sqlite")
    }
}
