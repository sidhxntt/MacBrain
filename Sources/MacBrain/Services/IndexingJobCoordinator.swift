import Foundation

actor IndexingJobCoordinator {
    private let database: MacBrainDatabase

    init(database: MacBrainDatabase) {
        self.database = database
    }

    func enqueue(sourceID: UUID, changedChunkIDs: [UUID]) async {
        guard !changedChunkIDs.isEmpty else { return }
        for kind in IndexingJobKind.allCases {
            let job = IndexingJob(sourceID: sourceID, kind: kind, chunkIDs: changedChunkIDs)
            try? await database.save(job: job)
        }
    }

    func cancel(sourceID: UUID) async {
        guard let jobs = try? await database.indexingJobs(sourceID: sourceID) else { return }
        for var job in jobs where job.state == .pending || job.state == .processing {
            job.state = .cancelled
            job.detail = "Cancelled because the source changed or was removed."
            job.updatedAt = .now
            try? await database.save(job: job)
        }
    }

    func processPending(using provider: any InferenceProvider, embeddingModel: String) async {
        guard let jobs = try? await database.pendingIndexingJobs() else { return }
        for job in jobs {
            guard !Task.isCancelled else { return }
            await process(job, using: provider, embeddingModel: embeddingModel)
        }
    }

    private func process(_ queuedJob: IndexingJob, using provider: any InferenceProvider, embeddingModel: String) async {
        var job = queuedJob
        guard await sourceExists(job.sourceID) else { return }
        job.state = .processing
        job.attempts += 1
        job.detail = "Processing local index work."
        job.updatedAt = .now
        guard await save(job) else { return }

        do {
            try Task.checkCancellation()
            switch job.kind {
            case .embedding:
                let chunks = try await database.chunks(ids: job.chunkIDs)
                let embeddings = try await provider.embeddings(model: embeddingModel, input: chunks.map(\.text))
                guard embeddings.count == chunks.count else {
                    throw ConnectorError.failed("The local embedding model returned incomplete results.")
                }
                for (chunk, embedding) in zip(chunks, embeddings) {
                    try Task.checkCancellation()
                    try await database.upsert(StoredEmbedding(
                        chunkID: chunk.id,
                        vector: embedding.values,
                        indexIdentifier: embeddingModel
                    ))
                }
                job.detail = "Embeddings saved for \(chunks.count) chunks."
            case .graphExtraction:
                // Deterministic evidence is extracted synchronously inside this durable background
                // job. A local chat model may enrich ambiguous text in a later job pass; it is
                // deliberately never invoked from search or the UI interaction path.
                let chunks = try await database.chunks(ids: job.chunkIDs)
                try await database.save(graph: DeterministicGraphExtractor().extract(from: chunks))
                job.detail = "Graph facts saved for \(chunks.count) chunks."
            }
            job.state = .completed
            job.updatedAt = .now
            _ = await save(job)
        } catch is CancellationError {
            job.state = .cancelled
            job.detail = "Cancelled before local index work completed."
            job.updatedAt = .now
            _ = await save(job)
        } catch {
            job.state = .failed
            job.detail = "Local index work failed: \(error.localizedDescription)"
            job.updatedAt = .now
            _ = await save(job)
        }
    }

    private func sourceExists(_ sourceID: UUID) async -> Bool {
        (try? await database.source(id: sourceID)) != nil
    }

    private func save(_ job: IndexingJob) async -> Bool {
        do {
            try await database.save(job: job)
            return true
        } catch {
            return false
        }
    }
}
