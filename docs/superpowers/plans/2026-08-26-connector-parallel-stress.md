# Connector Parallel Stress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all connected-source syncs concurrent, bounded by a two-minute deadline, incrementally indexed, and stress-verified across every connector kind.

**Architecture:** `SourceLibraryStore` will submit independent records through structured task groups while `LocalSourceCoordinator` owns a per-record in-flight task and terminal persistence. Each successful reconcile derives changed chunk IDs and enqueues durable indexing work; the store drives that work after every sync. Tests use deterministic probe connectors rather than personal macOS data.

**Tech Stack:** Swift 6, SwiftPM, XCTest, actors, structured concurrency, SQLite.

---

### Task 1: Prove and implement parallel source refresh

**Files:**
- Modify: `Tests/MacBrainTests/SourceConnectorTests.swift`
- Modify: `Sources/MacBrain/Stores/SourceLibraryStore.swift`

- [ ] Write a barrier-probe test with one record per `SourceConnectorKind` plus multiple browser profiles; invoke due refresh and assert every probe starts before release.
- [ ] Run the focused test and verify it fails because refresh awaits sources serially.
- [ ] Replace due/now/authorization refresh loops with a task group that awaits every per-record refresh and preserves source-specific activity.
- [ ] Run the focused test and verify it passes.

### Task 2: Bound every sync and preserve terminal outcomes

**Files:**
- Modify: `Tests/MacBrainTests/SourceConnectorTests.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceCoordinator.swift`

- [ ] Write a hanging-connector test asserting a configurable short test deadline marks the record failed and clears syncing state.
- [ ] Run the focused test and verify it fails because no deadline exists.
- [ ] Add a production two-minute deadline, injectable only for deterministic tests, with cancellation/error persistence and one in-flight task per record.
- [ ] Run the focused test and verify it passes.

### Task 3: Make successful syncs incrementally indexable and jobs terminal

**Files:**
- Modify: `Tests/MacBrainTests/SourceConnectorTests.swift`
- Modify: `Tests/MacBrainTests/IndexingJobCoordinatorTests.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceCoordinator.swift`
- Modify: `Sources/MacBrain/Services/IndexingJobCoordinator.swift`
- Modify: `Sources/MacBrain/Stores/SourceLibraryStore.swift`

- [ ] Write failing tests for generic and batched connector syncs queuing changed chunks, no-change resyncs queuing none, and missing-source jobs reaching cancelled.
- [ ] Run focused tests and verify the expected missing queue/terminal-state failures.
- [ ] Reconcile every connector through one changed-chunk path, process jobs after every store sync, and terminalize skipped/missing-source jobs.
- [ ] Run focused tests and verify they pass.

### Task 4: Correct incremental cache and batched finalization

**Files:**
- Modify: `Tests/MacBrainTests/SourceConnectorTests.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceCoordinator.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`

- [ ] Write failing tests for exact-boundary batches, no-change cache reuse, and add/edit/delete after a simulated five-minute resync.
- [ ] Implement final search-index reconciliation even when the final batch is empty, plus stale-document pruning where the connector supplies a full snapshot.
- [ ] Run focused tests and verify cache IDs remain stable for unchanged content and only changed documents receive work.

### Task 5: Connector-specific stress verification

**Files:**
- Modify: `Tests/MacBrainTests/SourceConnectorTests.swift`
- Modify: `Tests/StressTests/test_report.md`

- [ ] Run table-driven simulated stress for Notes, Mail, Calendar, Reminders, Contacts, Browser Profiles, Messages, Photos, Books, Folder, and Git.
- [ ] Run each connector’s focused automated test subset and the full SwiftPM suite.
- [ ] Record exact commands/results, marking macOS-permission-bound manual cases as not tested rather than passed.
