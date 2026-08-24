# Notch Brain Post-MVP Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this roadmap task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve the reliable Ollama-based MVP into a polished local work-memory product with stronger retrieval, bundled inference, richer context, and carefully confirmed actions.

**Architecture:** Preserve the native SwiftUI/AppKit shell and provider-neutral inference interface from the MVP. Extend the local data layer and connector system incrementally; every new context source and action remains permissioned, provenance-aware, observable, and independently disableable.

**Tech Stack:** Swift, SwiftUI, AppKit, SQLite/FTS5, local vector and graph storage, Ollama, MLX or llama.cpp, PDFKit, Vision, Accessibility APIs, FSEvents, Keychain, XCTest, XCUITest, Swift Package Manager/Xcode.

---

## Roadmap principles

- Keep all inference and user data local by default.
- Treat direct source evidence as more authoritative than graph inference.
- Keep the app useful when any connector, model, permission, or background job fails.
- Add one high-value workflow at a time and validate it with real users.
- Require explicit confirmation for every action that changes user or external data.
- Do not expand to a general operating-system agent until retrieval quality is demonstrably strong.

## Phase 0: MVP exit and beta baseline

**Outcome:** The MVP is stable enough to measure with real users.

**Files:** Existing MVP modules; add `docs/beta-metrics.md`, `NotchBrain/Diagnostics/DiagnosticsStore.swift`, and beta fixture projects.

- [ ] Run the clean-machine acceptance flow from the MVP plan on multiple Apple-silicon Macs.
- [ ] Record baseline metrics for first-run completion, index throughput, search latency, time-to-first-token, citation accuracy, memory pressure, and crash recovery.
- [ ] Add opt-in local diagnostics that record timings and error categories without document content.
- [ ] Build a fixed evaluation corpus containing notes, PDFs, Markdown, Git history, conflicting decisions, and intentionally irrelevant documents.
- [ ] Create a human-labeled question set for exact retrieval, semantic retrieval, multi-source synthesis, graph traversal, and unsupported questions.
- [ ] Establish release gates: grounded-answer rate, citation precision, acceptable cold-start latency, successful deletion, and no unexpected network calls.

## Phase 1: Retrieval and knowledge-graph quality

**Outcome:** The assistant gives more accurate answers across related documents and projects.

**Files:** `Retrieval/HybridSearch.swift`, `Retrieval/ContextAssembler.swift`, `Graph/KnowledgeGraph.swift`, `Indexing/Chunker.swift`, evaluation fixtures.

- [ ] Add source-type-aware chunking for code, Markdown headings, PDF pages, Git commits, and decision records.
- [ ] Add query intent classification for lookup, summary, comparison, timeline, relationship, and search-only requests.
- [ ] Add configurable retrieval fusion and evaluate keyword, vector, graph, recency, and source-diversity weights against the labeled corpus.
- [ ] Add a local reranking stage only for difficult or low-confidence queries, with a strict latency budget.
- [ ] Improve entity aliases, dates, project names, repository names, and person resolution using provenance and confidence thresholds.
- [ ] Add relationship conflict handling, superseding decisions, temporal validity, and source deletion cleanup.
- [ ] Display why a source or graph relationship was included without exposing internal scores as facts.
- [ ] Add regression tests for every previously corrected retrieval failure.

## Phase 2: High-value source connectors

**Outcome:** Users can recall decisions and context from the places they already work.

**Files:** `Indexing/SourceConnectors.swift`, connector-specific files, permission UI, documentation.

- [ ] Add Apple Notes through the least-privileged supported macOS automation path, with explicit notebook/account selection.
- [ ] Add local Apple Mail indexing only after defining a clear permission and privacy flow; preserve sender, recipients, subject, dates, thread IDs, and message provenance.
- [ ] Add imported meeting transcripts as a supported text source before attempting live meeting capture.
- [ ] Improve Git indexing with branches, commit ranges, changed files, authors, and issue/PR references when available locally.
- [ ] Add connector health, pause/resume, reauthorization, per-source deletion, and last-successful-sync status.
- [ ] Test connector denial, partial access, malformed data, changed permissions, duplicate content, and complete removal.

## Phase 3: Bundled local inference

**Outcome:** New users can use the app without separately installing Ollama, while power users can continue using Ollama.

**Files:** `Inference/InferenceProvider.swift`, new `Inference/MLXProvider.swift` or `Inference/LlamaCppProvider.swift`, model catalog/download UI, packaging configuration, `docs/model-support.md`.

- [ ] Choose MLX or llama.cpp based on a measured prototype for model loading, streaming, Apple GPU acceleration, embeddings, memory use, and redistribution licensing.
- [ ] Keep chat, embedding, cancellation, health, model download, and memory-status operations behind the existing provider protocol.
- [ ] Implement signed model metadata, resumable downloads, checksums, disk-space checks, versioned model storage, and safe cleanup.
- [ ] Make bundled lightweight inference the default and retain Ollama as an advanced provider selectable in settings.
- [ ] Detect available memory and recommend light, balanced, or deep models without automatically selecting an unsafe model.
- [ ] Add model warm-up, idle unload, generation cancellation, crash recovery, and user-visible resource status.
- [ ] Test clean installs with no Ollama, Ollama-only installs, provider switching, interrupted downloads, corrupted models, upgrades, and low-memory conditions.

## Phase 4: Product polish and daily workflow

**Outcome:** The app feels fast, predictable, and worth keeping open every day.

**Files:** `UI/SidebarView.swift`, `UI/ChatView.swift`, settings, onboarding, diagnostics, accessibility tests.

- [ ] Improve first-run onboarding with an immediate sample search, model size estimate, source selection, and privacy explanation.
- [ ] Add keyboard-first navigation, command palette, conversation pinning, saved searches, and project-scoped conversations.
- [ ] Add source previews, side-by-side evidence inspection, citation navigation, and copy-with-citations.
- [ ] Add index controls for pause, rebuild, remove source, exclude path, and storage cleanup.
- [ ] Add adaptive compact/expanded behavior, display-aware placement, reduced-motion support, and VoiceOver labels.
- [ ] Add local export/restore for conversations, memories, source configuration, and graph data.
- [ ] Measure and improve panel-open latency, search-first rendering, and streaming smoothness.

## Phase 5: Rich current-context integrations

**Outcome:** The assistant understands the user’s immediate work context without silently observing everything.

**Files:** `System/AppContextManager.swift`, new context providers, permission screens, context policy store.

- [ ] Add browser context through explicit user-triggered capture, never continuous collection by default.
- [ ] Add Xcode and VS Code current-file/repository context through supported integration points or user-selected files.
- [ ] Add terminal context from selected/copied output with visible expiration and redaction rules.
- [ ] Add Finder selection context for user-selected files and folders.
- [ ] Add screenshot/OCR capture using Screen Recording and Vision only after a dedicated permission explanation and visible capture state.
- [ ] Add context previews so users can remove or redact content before it reaches the local model.
- [ ] Enforce per-source enable/disable settings, context size limits, retention rules, and audit history.
- [ ] Test every integration with permission denied, app unavailable, stale context, sensitive-content redaction, and cancellation.

## Phase 6: Controlled action layer

**Outcome:** The assistant can help complete tasks without making unreviewed changes.

**Files:** new `Actions/ActionProtocol.swift`, `Actions/ActionRegistry.swift`, `Actions/ConfirmationCard.swift`, action-specific adapters, audit/history storage.

- [ ] Define typed read-only and mutating actions with input schemas, preview text, required permissions, reversibility, and provenance.
- [ ] Implement read-only actions first: open source, reveal in Finder, copy citation, create task-list text, and generate a meeting brief.
- [ ] Add confirmation cards for reminders, calendar events, notes, email drafts, and GitHub issues; show exact target and content before execution.
- [ ] Add cancellation, timeout, duplicate prevention, audit history, and undo where the destination supports it.
- [ ] Keep external-service credentials in Keychain and make every integration opt-in.
- [ ] Do not implement autonomous multi-step actions until individual actions pass reliability and confirmation testing.
- [ ] Test malformed action arguments, permission denial, network failure, duplicate execution, stale previews, cancellation, and partial completion.

## Phase 7: Commercial readiness

**Outcome:** The product is supportable, understandable, and ready for paid distribution.

**Files:** release configuration, onboarding/help content, diagnostics, privacy/security documentation, packaging scripts.

- [ ] Define the paid value proposition around private work memory and reliable evidence, not model access alone.
- [ ] Test pricing and retention with developers, consultants, researchers, and knowledge workers.
- [ ] Prepare signed/notarized distribution, update mechanism, crash reporting policy, support workflow, and recovery documentation.
- [ ] Publish clear hardware/model requirements and expected disk usage.
- [ ] Add an uninstall/data-removal flow that removes app data, indexes, memories, caches, and downloaded models when requested.
- [ ] Perform a security review of file access, logs, model downloads, Keychain usage, local ports, and action adapters.
- [ ] Run a final regression suite across supported macOS versions and Apple-silicon hardware profiles.

## Recommended sequencing

Complete retrieval quality and beta validation before adding more connectors. Add bundled inference only after the provider abstraction is exercised by the MVP and model-management requirements are measured. Add rich context only after privacy controls are clear. Add mutating actions last, after users trust citations and memory behavior.

## Post-MVP success criteria

- [ ] Users can complete first-run setup with minimal guidance.
- [ ] The app produces accurate, source-grounded answers on the evaluation corpus.
- [ ] Knowledge-graph relationships improve multi-document and multi-hop questions without increasing unsupported claims.
- [ ] Bundled inference works without Ollama on supported Apple-silicon Macs.
- [ ] Users can inspect, disable, delete, and export every indexed source and durable memory.
- [ ] Context capture is explicit, visible, scoped, and permissioned.
- [ ] Every mutating action has a reviewable confirmation step and reliable failure handling.
- [ ] The product saves users enough time to justify continued use and payment.
