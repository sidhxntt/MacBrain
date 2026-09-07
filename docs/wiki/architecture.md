# Architecture

## Runtime map

```text
SwiftUI sidebar/workspaces
  → ChatStore · SourceLibraryStore · MemoryStore · InferenceStore
  → application services and typed protocols
  → connectors · index coordinator · chunker · retrieval · context assembler
  → SQLite/FTS5/vector tables · Ollama local HTTP API · macOS frameworks
```

The UI never reads SQLite directly, parses an Ollama response, or implements a connector. Stores expose observable user-facing state; services own async I/O and domain decisions; models carry stable source, chunk, citation, context, and session identifiers. This creates test seams for filesystem access, database work, inference, permissions, screens, clock, source opening, and panel behavior.

## Data flow

1. The user activates the panel and selects a query or explicit context attachment.
2. `ChatQueryIntentRouter`/`LocalQueryPlanner` classify search, system question, memory command, or knowledge question.
3. `SourceQueryScope` applies source permissions and exclusions; retrieval searches only committed local documents.
4. Hybrid retrieval deduplicates, diversifies, and emits `RetrievalEvidence` with source provenance.
5. `ContextAssembler` bounds evidence, conversation turns, and authorized live context to the model budget.
6. `OllamaProvider` streams answer deltas through `StreamingChatResponder`; citations are validated and rendered beside their evidence.
7. The local session records query, evidence IDs, response, model metadata, and recoverable errors.

## Persistence and consistency

`MacBrainDatabase` is the sole MVP persistence foundation: sources, documents, chunks, embeddings, jobs, sessions/messages, citations, memories, settings, and migrations live in SQLite. FTS5/vector records reference stable document/chunk IDs. Multi-record updates use transactions; a source generation is visible to retrieval only after its full commit. A refresh failure preserves the last verified generation, while deletion removes configuration and retrieval eligibility.

## Concurrency and failure model

Indexing, embedding, retrieval, connector reads, and generation run away from the main actor. Services return async values/streams with cancellation and actionable errors. A connector failure is isolated to its source; vector/graph degradation falls back to lexical retrieval; an unavailable Ollama backend leaves search-only behavior available. Logs carry coarse redacted diagnostics, not source content.
