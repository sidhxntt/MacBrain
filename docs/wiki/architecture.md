# Architecture

## Product boundary

NotchBrain is a native macOS app, not a remote service. SwiftUI owns presentation; AppKit owns panel/window behavior; local actors and services own durable data, connector I/O, retrieval, and inference boundaries. The MVP is a local retrieval assistant, not an autonomous agent with invisible filesystem or external-action authority.

## Runtime layers

```text
SwiftUI sidebar, workspaces, and settings
        ↓ @MainActor stores
ChatStore · SourceLibraryStore · MemoryStore · InferenceStore
        ↓ typed services and actors
panel policy · connectors · source coordinator · retrieval · responder
        ↓ local dependencies
SQLite / FTS5 / vector tables · Ollama HTTP · macOS permission frameworks
```

Views do not parse browser databases, perform SQL, choose window level, read a connector, or parse Ollama streams. Stores publish user-facing state. Services carry domain policy and use protocols/models as test seams. The architecture supports a failure in one connector or provider without invalidating every other local capability.

## Source-to-answer flow

1. A user selects a source or attaches temporary context intentionally.
2. A connector returns normalized documents with stable identity and provenance.
3. The source coordinator hashes, chunks, and reconciles documents in SQLite.
4. A complete commit updates source health and makes that state retrieval eligible.
5. The query planner and source scope select the relevant local route and authorized corpus.
6. Hybrid retrieval produces bounded `RetrievalEvidence`; citation policy filters it.
7. Search-only returns evidence, or the streaming responder sends bounded evidence/context to the local provider.
8. Citation validation and the chat store render source cards and persist the local session.

## Persistence and consistency

`MacBrainDatabase` is the single local persistence foundation. It holds connector records, sources, documents, chunks, embeddings, graph records, indexing jobs, conversations, messages, citations, memories, and migrations. FTS/vector records reference stable local IDs. Multi-record mutations use SQLite transactions; a reconciled generation preserves unchanged rows, updates changed rows, removes absent rows, and updates health as one commit.

The database target name is currently `MacBrain`; that is an implementation identifier, not the public product name. A connector failure preserves the last verified generation. Source removal deletes its retrieval state rather than leaving orphaned FTS content.

## Concurrency and degradation

`@MainActor` UI stores do not own long-running work. Actors serialize database and coordinator state; async services support cancellation. A failed vector/graph route falls back to lexical retrieval; an unavailable local inference provider leaves search-only/evidence behavior available; an inaccessible connector becomes source-local health state. Context, evidence, and conversation are bounded before a provider request, and diagnostics avoid source/prompt content.

## Security boundary

The app receives access through explicit connector configuration, security-scoped folder access, and macOS permissions. Source selection does not authorize unrelated live context. The model receives only an assembled local prompt; it does not hold a database handle or connector permission. Future external write actions must pass through an explicit confirmation boundary.
