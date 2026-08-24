# Notch Brain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private, local-first macOS sidebar that indexes user-selected work sources, retrieves grounded evidence, answers through Ollama, and manages durable memories.

**Architecture:** A SwiftUI interface runs in an AppKit-managed edge-attached panel. A local application service owns indexing, SQLite/FTS5/vector retrieval, a lightweight SQLite knowledge graph, memories, context assembly, and Ollama streaming. The UI depends on stable service protocols so Ollama can later be replaced by bundled MLX or llama.cpp without changing product behavior.

**Tech Stack:** Swift, SwiftUI, AppKit, SQLite/FTS5, sqlite-vec or equivalent vector extension, PDFKit, Git CLI, Ollama local HTTP streaming API, Keychain, FSEvents/file watchers, XCTest, Swift Package Manager/Xcode.

---

## Scope and product decisions

The first release includes the edge sidebar, global shortcut, local Ollama setup, lightweight default chat and embedding models, selected-folder/Markdown/plain-text/PDF/Git indexing, hybrid retrieval, citations, source opening, clipboard/selected-text context, local conversations, and explicit save/forget memories.

Email, Apple Notes, screenshots/OCR, calendar/reminder actions, external-service mutations, autonomous coding tasks, and bundled inference are post-MVP. The schema and inference interfaces must leave room for them, but they must not block the first usable release.

The knowledge graph is included from the beginning as a lightweight SQLite graph. Entity and relationship extraction runs asynchronously and improves retrieval; basic keyword/vector search remains functional if graph extraction is unavailable.

## File and module map

Create a package-first structure unless the existing repository already establishes an Xcode structure:

- `MacBrain/MacBrainApp.swift` — app entry point and scene lifecycle.
- `MacBrain/UI/SidebarPanelController.swift` — AppKit panel creation, positioning, focus, resize, dismissal.
- `MacBrain/UI/SidebarView.swift` — compact/expanded chat shell and navigation.
- `MacBrain/UI/ChatView.swift` — messages, streaming state, composer, actions.
- `MacBrain/UI/SourceCitationView.swift` — source chips/cards and open-source actions.
- `MacBrain/UI/MemoryView.swift` — inspect, edit, delete, export memories.
- `MacBrain/System/GlobalShortcutManager.swift` — global shortcut registration.
- `MacBrain/System/AppContextManager.swift` — clipboard, selected text, active app/window, permissions.
- `MacBrain/System/PermissionManager.swift` — explain and track Accessibility/filesystem permissions.
- `MacBrain/Inference/InferenceProvider.swift` — provider-neutral streaming protocol and model status types.
- `MacBrain/Inference/OllamaProvider.swift` — Ollama health checks, model downloads, embeddings, streaming chat.
- `MacBrain/Indexing/IndexCoordinator.swift` — source registration, scheduling, incremental indexing, stale pruning.
- `MacBrain/Indexing/SourceConnectors.swift` — files, Markdown, plain text, PDF, Git connectors.
- `MacBrain/Indexing/Chunker.swift` — deterministic text chunking with source offsets.
- `MacBrain/Retrieval/HybridSearch.swift` — FTS5/vector/graph retrieval, scoring, reranking.
- `MacBrain/Retrieval/ContextAssembler.swift` — token-bounded evidence context and citation mapping.
- `MacBrain/Graph/KnowledgeGraph.swift` — entities, aliases, mentions, relationships, provenance.
- `MacBrain/Memory/MemoryStore.swift` — explicit durable memories and deletion/export.
- `MacBrain/Storage/Database.swift` and `MacBrain/Storage/Migrations.swift` — SQLite connection, migrations, transactions.
- `MacBrain/Storage/Models.swift` — shared persisted model types.
- `MacBrain/Privacy/ExclusionRules.swift` — user exclusions and secret/build-folder filters.
- `MacBrainTests/` — unit, integration, retrieval, permission, and UI-facing tests.
- `docs/architecture.md`, `docs/privacy.md`, `docs/model-support.md` — decisions users and maintainers need.

## Delivery phases

### Task 1: Establish the macOS application shell

**Files:** Create the app entry point, panel controller, sidebar shell, and initial test target.

- [ ] Create a SwiftUI macOS app with a single dependency-free launch path.
- [ ] Implement an `NSPanel` that can be shown/hidden, stays above normal windows, avoids stealing focus when dismissed, and anchors to the active display edge.
- [ ] Add compact and expanded layout states with keyboard navigation behavior.
- [ ] Add an app-owned logger for panel show/hide, display changes, and failures.
- [ ] Write tests for panel state transitions and display selection using injected panel/display abstractions.
- [ ] Verify the app launches, opens from a temporary button, resizes, and dismisses cleanly on one and multiple displays.

### Task 2: Add global activation and permissions

**Files:** `System/GlobalShortcutManager.swift`, `System/PermissionManager.swift`, `System/AppContextManager.swift`.

- [ ] Register a configurable global shortcut and route it to toggle the panel.
- [ ] Add Accessibility permission status and a user-facing explanation before requesting it.
- [ ] Implement clipboard capture with an explicit enable/disable setting.
- [ ] Implement selected-text capture through the Accessibility API where permitted, with clipboard fallback and actionable failure messages.
- [ ] Capture active application and window title without indexing or transmitting content automatically.
- [ ] Test shortcut registration, permission-denied behavior, clipboard limits, and context redaction.

### Task 3: Build the SQLite storage foundation

**Files:** `Storage/Database.swift`, `Storage/Migrations.swift`, `Storage/Models.swift`.

- [ ] Create migrations for sources, documents, chunks, embeddings, conversations, messages, memories, entities, aliases, mentions, relationships, and indexing jobs.
- [ ] Store source provenance on every chunk, entity mention, relationship, memory, and citation candidate.
- [ ] Add FTS5 over normalized chunk text and indexes for source IDs, hashes, timestamps, entity names, and relationship endpoints.
- [ ] Add vector storage through `sqlite-vec` or an equivalent local extension behind a `VectorStore` protocol.
- [ ] Use transactions for document replacement and graph updates so interrupted indexing cannot leave partial source state.
- [ ] Add migration tests, rollback-safe error tests, and a temporary-database integration test.

### Task 4: Implement Ollama setup and provider abstraction

**Files:** `Inference/InferenceProvider.swift`, `Inference/OllamaProvider.swift`, model setup UI, `docs/model-support.md`.

- [ ] Define provider methods for health, installed models, model download progress, embedding, streaming generation, cancellation, and unload/status.
- [ ] Detect Ollama availability and distinguish missing runtime, unavailable server, missing chat model, missing embedding model, and insufficient memory.
- [ ] Build first-run setup: choose lightweight defaults, download models, show progress, test chat and embedding, and explain disk/RAM requirements.
- [ ] Default to a quantized 3B–4B chat model plus a lightweight embedding model; allow later 7B–8B upgrades.
- [ ] Parse Ollama streaming responses incrementally, support stop/cancel, timeouts, and actionable errors.
- [ ] Test the provider against recorded local responses and a mock server; reserve one manual test against Ollama.

### Task 5: Implement source connectors and incremental indexing

**Files:** `Indexing/SourceConnectors.swift`, `Indexing/IndexCoordinator.swift`, `Indexing/Chunker.swift`, `Privacy/ExclusionRules.swift`.

- [ ] Add user-selected folder registration with security-scoped bookmark persistence.
- [ ] Extract Markdown/plain text while preserving paths, titles, headings, dates, and byte/line offsets.
- [ ] Extract PDF text through PDFKit and retain page numbers for citations.
- [ ] Detect Git repositories, index tracked text files and commit metadata, and identify the active repository/branch for context.
- [ ] Compute content hashes and modification metadata; skip unchanged files and prune deleted/moved sources.
- [ ] Apply exclusions for credentials, secret files, build outputs, dependency directories, and user-defined paths before extraction.
- [ ] Chunk deterministically with overlap and stable chunk IDs.
- [ ] Queue embeddings and graph extraction in background jobs without blocking the sidebar.
- [ ] Test supported formats, unreadable files, duplicate paths, changed/deleted files, exclusions, cancellation, and restart recovery.

### Task 6: Add embeddings, hybrid retrieval, and citations

**Files:** `Retrieval/HybridSearch.swift`, `Retrieval/ContextAssembler.swift`.

- [ ] Embed new/changed chunks locally and replace stale vectors transactionally.
- [ ] Implement FTS5 keyword search and vector similarity search with normalized scores.
- [ ] Combine keyword, vector, recency, source-type, and optional graph scores using configurable weights.
- [ ] Deduplicate adjacent chunks and cap evidence by token budget, preserving source diversity.
- [ ] Return a typed evidence object containing source title/type/path/date, excerpt, offsets/page, score, and citation ID.
- [ ] Assemble a prompt that requires evidence-grounded answers, explicit uncertainty, and citation IDs; support search-only mode.
- [ ] Test exact-match retrieval, semantic retrieval, low-confidence results, duplicate sources, token limits, and citation-to-excerpt integrity.

### Task 7: Add the knowledge graph

**Files:** `Graph/KnowledgeGraph.swift`, storage models/migrations, indexing and retrieval integration.

- [ ] Define initial entity types: person, project, repository, document, decision, organization, topic, and date.
- [ ] Define relationship types: `mentions`, `belongs_to_project`, `works_on`, `made_decision`, `supported_by`, `related_to`, and `supersedes`.
- [ ] Extract candidate entities and relations from chunks asynchronously using deterministic heuristics first and the local chat model only where useful.
- [ ] Normalize aliases and preserve confidence plus source provenance for every candidate.
- [ ] Add graph expansion for retrieved entities, limited by depth and score to prevent noisy context growth.
- [ ] Make graph-derived evidence visibly distinguishable from direct source excerpts.
- [ ] Test alias merging, conflicting relations, deletion/reindex cleanup, provenance, graph expansion limits, and graph-unavailable fallback.

### Task 8: Implement conversations, memories, and chat UX

**Files:** `UI/ChatView.swift`, `UI/SourceCitationView.swift`, `UI/MemoryView.swift`, `Memory/MemoryStore.swift`.

- [ ] Persist conversations and messages locally with timestamps and model metadata.
- [ ] Stream answers into the UI while showing retrieved sources as early as possible.
- [ ] Add follow-ups, retry, stop, copy, clear conversation, source opening, and search-only mode.
- [ ] Implement explicit commands for save, forget, list, edit, delete, delete-all, and export memories.
- [ ] Keep indexed content separate from assistant-created memories in storage and UI.
- [ ] Require confirmation for delete-all and show what will be removed; export portable JSON/Markdown without secrets.
- [ ] Test streaming interruption, restart recovery, citation rendering, memory CRUD, export/import validation, and empty-result UX.

### Task 9: Add live context and model/resource safeguards

**Files:** `System/AppContextManager.swift`, settings/resource UI, inference and retrieval layers.

- [ ] Add opt-in selected text and clipboard context to the next prompt only, with clear visible indicators.
- [ ] Detect active repository/branch and attach it as scoped context when available.
- [ ] Monitor memory pressure, model size, embedding queue, and index status.
- [ ] Apply context-size limits, unload idle models where supported, and warn before selecting models that may not fit.
- [ ] Ensure no cloud networking is required by the app and document every local network permission used for Ollama.
- [ ] Test Ollama unavailable, model failure, memory pressure, oversized context, permission denial, and interrupted indexing.

### Task 10: Privacy, packaging, and release hardening

**Files:** entitlements, `docs/privacy.md`, release configuration, test fixtures, packaging scripts.

- [ ] Audit all filesystem and Accessibility access against user-selected scope.
- [ ] Store provider settings and any future tokens in Keychain; never hardcode secrets or log document contents.
- [ ] Add a privacy screen showing indexed locations, exclusions, memories, and deletion controls.
- [ ] Validate sandbox/security-scoped bookmarks, code signing, notarization prerequisites, and multi-display behavior.
- [ ] Add launch, indexing, retrieval, generation, and crash-recovery performance tests on the target 24 GB Apple-silicon machine.
- [ ] Run a clean-machine acceptance test: install app, install Ollama, download lightweight models, index fixtures, ask cited questions, open sources, save/forget memory, and remove all data.
- [ ] Define release gates: no unsupported claim without citation, no data sent externally, recoverable indexing failures, successful deletion, and acceptable first-answer latency.

## Suggested execution order

Complete Tasks 1–4 before building the full retrieval pipeline so the app can be launched and the local inference dependency can be validated early. Then execute Tasks 5–7 as the data foundation, followed by Tasks 8–10 for product integration and release hardening.

Each task should be delivered as a small commit after its tests pass. Do not begin email, Notes, OCR, calendar actions, bundled inference, or autonomous coding until the release gates pass for the MVP.

## Verification checklist

- [ ] New user can install the app, understand local-only behavior, install Ollama, and download recommended models.
- [ ] User can index only selected folders and see indexing progress/status.
- [ ] Changed and deleted files update the index without full reindexing.
- [ ] Search returns useful direct excerpts before generation completes.
- [ ] Answers cite exact sources and state uncertainty when evidence is weak.
- [ ] Graph relationships improve multi-hop questions without becoming required for basic search.
- [ ] User can open the original file/repository source.
- [ ] Clipboard and selected text are opt-in and visibly scoped.
- [ ] Memories are explicitly created, separately labeled, editable, exportable, and deletable.
- [ ] No user content leaves the machine during normal operation.
- [ ] The app remains usable when Ollama, a model, a permission, a file, or an index job fails.

## Major risks and mitigations

- **Weak local answers:** use citations-first retrieval, lightweight-model defaults with optional upgrades, strict context limits, and a search-only fallback.
- **Setup friction:** integrate Ollama detection and model downloads into onboarding; show disk/RAM estimates before download.
- **Graph noise:** keep direct evidence primary, attach confidence/provenance, use bounded expansion, and allow graph fallback.
- **macOS permission complexity:** request permissions only when a feature needs them and test denial paths as first-class flows.
- **Large indexes:** incremental hashing, background work, exclusions, bounded embeddings, and visible storage controls.
- **Future bundled inference cost:** keep the provider-neutral interface and model lifecycle separate from chat/retrieval UI.

## Definition of done

The MVP is complete when a clean-machine user can open the sidebar globally, index selected local sources, ask a question about their work, receive a streamed answer with exact citations, open the sources, ask a follow-up, save or forget a memory, and use the entire workflow without a hosted AI API or silent broad filesystem indexing.
