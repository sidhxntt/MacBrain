import Foundation
import XCTest
@testable import MacBrain

final class IndexingJobCoordinatorTests: XCTestCase {
    func testEnqueuePersistsEmbeddingAndGraphJobsForChangedChunks() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let sourceID = UUID()
        try await database.save(source: StoredSource(id: sourceID, kind: "folder", displayName: "Work"))
        let coordinator = IndexingJobCoordinator(database: database)

        await coordinator.enqueue(sourceID: sourceID, changedChunkIDs: [UUID(), UUID()])
        let jobs = try await database.indexingJobs(sourceID: sourceID)

        XCTAssertEqual(Set(jobs.map(\.kind)), [.embedding, .graphExtraction])
        XCTAssertTrue(jobs.allSatisfy { $0.state == .pending })
        XCTAssertTrue(jobs.allSatisfy { $0.chunkIDs.count == 2 })
    }

    func testCancelMarksQueuedJobsWithoutRemovingAuditHistory() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let sourceID = UUID()
        try await database.save(source: StoredSource(id: sourceID, kind: "folder", displayName: "Work"))
        let coordinator = IndexingJobCoordinator(database: database)
        await coordinator.enqueue(sourceID: sourceID, changedChunkIDs: [UUID()])

        await coordinator.cancel(sourceID: sourceID)
        let jobs = try await database.indexingJobs(sourceID: sourceID)

        XCTAssertTrue(jobs.allSatisfy { $0.state == .cancelled })
    }

    func testProcessingEmbedsChangedChunksAndCompletesGraphHook() async throws {
        let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
        let sourceID = UUID()
        try await database.save(source: StoredSource(id: sourceID, kind: "folder", displayName: "Work"))
        let document = StoredDocument(
            sourceID: sourceID,
            externalID: "brief.md",
            title: "Brief",
            text: "Local embedding evidence",
            sourceLabel: "Work"
        )
        let chunk = StoredChunk(documentID: document.id, sourceID: sourceID, text: document.text, startOffset: 0, endOffset: document.text.utf16.count)
        try await database.replace(document: document, chunks: [chunk], embeddings: [])
        let coordinator = IndexingJobCoordinator(database: database)

        await coordinator.enqueue(sourceID: sourceID, changedChunkIDs: [chunk.id])
        await coordinator.processPending(using: FixedEmbeddingProvider(), embeddingModel: "test-embed")

        let jobs = try await database.indexingJobs(sourceID: sourceID)
        let nearest = try await database.nearest(to: [0.5, 0.5], limit: 1)
        XCTAssertTrue(jobs.allSatisfy { $0.state == .completed })
        XCTAssertEqual(nearest, [chunk.id])
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexingJobCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("macbrain.sqlite")
    }
}

private struct FixedEmbeddingProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus { .ready(models: []) }
    func streamChat(model: String, messages: [InferenceChatMessage]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
    func embeddings(model: String, input: [String]) async throws -> [InferenceEmbedding] { input.map { _ in InferenceEmbedding(values: [0.5, 0.5]) } }
    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> { AsyncThrowingStream { $0.finish() } }
}
