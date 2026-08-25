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

- [x] Create `Database`, `Migrations`, and typed storage models.
- [x] Add migrations with version numbers and transactional execution.
- [x] Add SQLite FTS5 over normalized chunk text.
- [x] Add a `VectorStore` protocol and a local SQLite-backed cosine-similarity equivalent.
- [x] Add indexes for hashes, source IDs, timestamps, entity names, and relationship endpoints.
- [x] Ensure document replacement and graph updates are atomic.
- [x] Add temporary-database integration tests for migrations, persistence, FTS/vector search, source mirroring, and interrupted transactions.

## Exit criteria

A fresh database migrates successfully, persists and reloads sources (including connector configuration), documents, conversations, messages, and memories; supports FTS5 and local vector search; and cannot retain half-written documents after a failed transaction. The app mirrors selected sources and restores durable chat sessions from this database.

## Cache and refresh behavior

- Connector configuration, prior document hashes, and indexed chunk identities persist locally.
- A source that synced successfully within the five-minute refresh interval is not queried again when MacBrain reopens.
- Identical connector output is a cache hit: MacBrain keeps the existing document/chunk entries instead of rebuilding the local index.
- macOS grants Automation, Files and Folders, and Full Disk Access separately through its system permission store. MacBrain reuses a granted permission; it does not intentionally request it again on every launch.
