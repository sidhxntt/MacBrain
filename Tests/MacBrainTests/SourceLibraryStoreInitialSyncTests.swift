import Foundation
import Testing
@testable import MacBrain

struct SourceLibraryStoreInitialSyncTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func addAndSyncDrainsQueuedEnrichmentAfterTheVerifiedCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "macbrain-store-initial-sync-" + UUID().uuidString,
            isDirectory: true
        )
        let database = try MacBrainDatabase(
            url: directory.appendingPathComponent("macbrain.sqlite")
        )
        let repository = LocalSourceRepository(
            fileURL: directory.appendingPathComponent("local-sources.json"),
            database: database
        )
        try await repository.bootstrap()
        let coordinator = LocalSourceCoordinator(
            repository: repository,
            indexingJobs: IndexingJobCoordinator(database: database),
            connectors: [StoreInitialSyncConnector()]
        )
        let store = SourceLibraryStore(
            repository: repository,
            coordinator: coordinator,
            database: database
        )
        store.configureAutomaticIndexing(
            using: StoreInitialSyncProvider(),
            selectedEmbeddingModel: { "test-embed" }
        )

        store.addAndSync(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )
        while store.isSyncing(kind: .appleNotes)
            || store.records.first?.status == .syncing
        {
            await Task.yield()
        }

        let record = try #require(store.records.first)
        let jobs = try await database.indexingJobs(sourceID: record.id)
        #expect(record.status == .ready)
        #expect(jobs.count == 2)
        #expect(jobs.allSatisfy { $0.state == .completed })
        #expect(try await database.nearest(to: [0.25, 0.75], limit: 1).count == 1)
    }
}

private struct StoreInitialSyncConnector: SourceConnector {
    let kind = SourceConnectorKind.appleNotes

    func sync(record: ConnectorRecord) async throws -> [ConnectorDocument] {
        [
            ConnectorDocument(
                connectorID: record.id,
                externalID: "initial-note",
                title: "Initial note",
                text: "INITIAL-ENRICHMENT is immediately indexed",
                sourceLabel: "Apple Notes"
            )
        ]
    }
}

private struct StoreInitialSyncProvider: InferenceProvider {
    func status() async -> InferenceProviderStatus { .ready(models: []) }

    func streamChat(
        model: String,
        messages: [InferenceChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func embeddings(
        model: String,
        input: [String]
    ) async throws -> [InferenceEmbedding] {
        input.map { _ in InferenceEmbedding(values: [0.25, 0.75]) }
    }

    func pull(model: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
