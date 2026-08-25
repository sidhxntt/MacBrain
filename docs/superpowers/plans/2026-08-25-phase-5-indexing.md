# Phase 5 Indexing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn explicit local connectors into a citation-quality, incremental local index with cancellable downstream work.

**Architecture:** Keep connector UI and consent flow unchanged. Connectors continue to emit normalized `ConnectorDocument` values; a new indexing layer fingerprints files, splits documents deterministically into stable chunks, and persists source state. A cancellable local job coordinator processes embeddings and graph-extraction hooks only after source writes succeed.

**Tech Stack:** Swift 6, SwiftPM, Foundation, PDFKit, CryptoKit, SQLite/FTS5, XCTest.

---

### Task 1: Citation-ready document chunks

**Files:**
- Create: `Sources/MacBrain/Services/DocumentChunker.swift`
- Modify: `Sources/MacBrain/Models/SourceConnector.swift`
- Modify: `Sources/MacBrain/Services/LocalFileIndexer.swift`
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Test: `Tests/MacBrainTests/DocumentChunkerTests.swift`

- [x] Write failing tests proving fixed-size overlap, stable IDs, Markdown line ranges, and PDF page numbers.
- [ ] Run `swift test --filter DocumentChunkerTests`; confirm failures identify missing chunker behavior.
- [x] Implement value-type chunk input/output and deterministic SHA-256 IDs from source external ID plus UTF-16 bounds.
- [x] Parse Markdown headings and line numbers; emit each PDF page as a separately addressable normalized document.
- [x] Replace one-document/one-chunk writes with chunker output in SQLite persistence.
- [ ] Run focused tests; then `swift test`.

### Task 2: Fingerprinted source scans and source exclusions

**Files:**
- Create: `Sources/MacBrain/Services/FileFingerprint.swift`
- Modify: `Sources/MacBrain/Models/SourceConnector.swift`
- Modify: `Sources/MacBrain/Services/LocalFileIndexer.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Modify: `Sources/MacBrain/Views/SourceManagerView.swift`
- Test: `Tests/MacBrainTests/LocalFileIndexerTests.swift`
- Test: `Tests/MacBrainTests/LocalSourceRepositoryTests.swift`

- [ ] Write failing tests proving unchanged path/size/modification fingerprints bypass file reads; changed and deleted paths update the index; supplied exclude paths remove matching descendants.
- [ ] Run focused tests and verify red state.
- [x] Persist per-source fingerprint map and user exclusion patterns in connector configuration.
- [x] Index recursively while excluding dependency/build folders and configured paths; retain hidden and secret files unless user excludes them.
- [x] Persist refreshed fingerprints only after a successful source transaction; preserve existing source content after cancellation/failure.
- [ ] Run focused tests and full suite.

### Task 3: Cancellable indexing jobs

**Files:**
- Create: `Sources/MacBrain/Models/IndexingJob.swift`
- Create: `Sources/MacBrain/Services/IndexingJobCoordinator.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceCoordinator.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Test: `Tests/MacBrainTests/IndexingJobCoordinatorTests.swift`

- [ ] Write failing tests proving jobs enqueue only for new/changed chunks, cancel cleanly, survive restart as pending work, and never mutate deleted sources.
- [ ] Run focused tests and verify red state.
- [x] Implement actor-isolated persistent job queue with embedding and graph-extraction job kinds, status, retry count, and source ownership.
- [x] Invoke jobs after successful source writes; cancel jobs for removed sources and provide no-op graph hook until Phase 7.
- [ ] Run focused tests and full suite.

### Task 4: Robust source lifecycle verification

**Files:**
- Modify: `Tests/MacBrainTests/SourceConnectorTests.swift`
- Modify: `Tests/MacBrainTests/MacBrainDatabaseTests.swift`
- Create: `Tests/MacBrainTests/LocalSourceCoordinatorTests.swift`
- Modify: `docs/MVP/05-indexing.md`

- [ ] Write failing integration tests for malformed input, permission denial, duplicate documents, cancellation, stale bookmark handling, restart recovery, deleted files, and moved-file delete/add behavior.
- [ ] Run focused tests and verify red state.
- [x] Add only necessary production fixes discovered by these tests.
- [x] Update phase checklist to distinguish complete requirements from later FSEvents work.
- [ ] Run `swift test`; build with `swift build`; do not launch the app.

### Task 5: Completion audit

**Files:**
- Modify: `docs/MVP/05-indexing.md`

- [x] Verify every Phase 5 exit criterion against source code and tests.
- [x] Record commands and outcomes in phase documentation.
- [ ] Commit focused changes on `codex/phase-5` after all tests pass.
