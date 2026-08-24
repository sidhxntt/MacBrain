# Notch Brain Architecture

## Product boundary

Notch Brain is a native macOS app. SwiftUI owns presentation; AppKit owns system-level window behavior. The MVP is a local RAG assistant, not a general autonomous agent.

## Runtime layers

```text
SidebarPanel / SwiftUI views
        ↓ stable view models and service protocols
Application services
  ShortcutManager · PermissionManager · ContextManager · ConversationStore
        ↓ async interfaces
Local knowledge service
  IndexCoordinator · Connectors · Chunker · Embeddings · HybridSearch
  ContextAssembler · MemoryStore · InferenceProvider
        ↓
SQLite database + FTS5 + vector tables + local Ollama HTTP API
```

The UI must not know SQLite schemas, Ollama request formats, connector internals, or embedding details. Services expose typed models, async streams for progress/tokens, cancellation, and actionable errors.

## MVP components

- **Sidebar shell**: an edge-attached `NSPanel` or borderless `NSWindow`, always-on-top within the intended scope, resizable, focusable, multi-display aware, and dismissible.
- **Activation**: global shortcut and optional edge activation; permission failures explain recovery.
- **Context manager**: explicit clipboard/selected-text capture plus active app/window and repository/branch metadata when available. Each item has source, timestamp, size, expiration, and redaction state.
- **Index coordinator**: accepts user-selected roots, discovers supported files, hashes content, indexes changed items, prunes stale records, reports progress, and supports cancellation/restart recovery.
- **Connectors**: Markdown/plain text, PDF, selected folders, and Git repository metadata/history in MVP. Each connector returns normalized documents with stable source identity and display metadata.
- **Retrieval**: FTS5 keyword search and vector search are fused, deduplicated, diversified, optionally graph-expanded, and capped by evidence/context budgets.
- **Answering**: `InferenceProvider` streams answer deltas and reports citations mapped to evidence IDs. Search-only mode returns evidence without generation.
- **Memory**: explicit save, inspect, edit, delete, forget, and export. Memories never masquerade as source evidence.

## Data flow

1. User opens the panel and optionally attaches visible context.
2. Query is classified as search, memory command, or knowledge question.
3. Retrieval searches indexed chunks and applies scope/exclusion rules.
4. `ContextAssembler` selects bounded evidence and conversation turns, preserving source IDs and excerpts.
5. The provider receives a structured prompt that requires evidence-grounded claims and uncertainty when evidence is insufficient.
6. Tokens stream to the UI; source cards can appear as soon as retrieval completes.
7. Conversation state stores the query, evidence IDs, response, model metadata, and errors locally.

## Persistence

SQLite is the sole MVP persistence foundation. Logical records include sources, documents, chunks, embeddings, indexing jobs, conversations, messages, citations, memories, settings, and schema migrations. FTS5 and vector storage reference stable document/chunk IDs. Writes that update multiple records use transactions; interrupted indexing must not expose half-written documents.

Source identity is based on connector type plus canonical location and content metadata. Re-indexing updates changed documents; deletion or movement marks stale records and removes them from retrieval after a successful indexing pass.

## Concurrency and failure boundaries

Indexing, embedding, retrieval, and generation run off the main actor. UI updates are delivered through observable state or async sequences and remain cancellable. A failed connector affects only its source; a failed graph/vector path falls back to keyword search; unavailable Ollama leaves search-only mode usable. Errors carry recovery guidance and are safe to display without leaking content into logs.

## Testing seams

Use protocols for panel/display behavior, shortcut registration, permissions, filesystem access, clock, database, embeddings, inference, and source opening. Unit tests cover chunking, hashing, fusion, context budgets, citation mapping, redaction, memory commands, and migration behavior. Integration tests use temporary databases and fixture repositories/documents. Manual acceptance covers multi-monitor behavior, permissions, Ollama setup, streaming cancellation, and clean-machine release installation.

## Future extensions

Apple Notes, email, screenshots/OCR, browser/editor integrations, calendar/reminder actions, external service actions, and bundled MLX/`llama.cpp` inference plug into the same connector, action, context-provider, or `InferenceProvider` boundaries. They require explicit consent and must not change MVP defaults.
