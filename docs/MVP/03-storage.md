# Phase 03 — SQLite Storage Foundation

## Goal

Create durable local storage for sources, chunks, vectors, conversations, memories, graph data, and indexing state.

## Schema areas

- Sources and registered folders.
- Documents, content hashes, modification state, and deletion state.
- Chunks with offsets, page/line metadata, and source provenance.
- Embeddings and vector-index identifiers.
- Conversations and messages.
- Memories with explicit user ownership and timestamps.
- Entities, aliases, mentions, relationships, and relationship provenance.
- Indexing jobs and migration state.

## Implementation sequence

- [ ] Create `Database`, `Migrations`, and typed storage models.
- [ ] Add migrations with version numbers and transactional execution.
- [ ] Add SQLite FTS5 over normalized chunk text.
- [ ] Add a `VectorStore` protocol and integrate `sqlite-vec` or the selected equivalent.
- [ ] Add indexes for hashes, source IDs, timestamps, entity names, and relationship endpoints.
- [ ] Ensure document replacement and graph updates are atomic.
- [ ] Add temporary-database integration tests for migrations, constraints, and interrupted transactions.

## Exit criteria

A fresh database migrates successfully, persists and reloads all core records, supports FTS5 and vector storage, and cannot retain half-written documents after a failed transaction.
