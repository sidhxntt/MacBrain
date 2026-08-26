# Reliable Connector Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make connect, initial sync, verified searchability, restart recovery, and five-minute refresh one reliable nonblocking lifecycle for every connector.

**Architecture:** Preserve connector adapters and the `SourceLibraryStore` presentation boundary, while making SQLite the authoritative production store. A repository bootstrap imports/repairs legacy JSON, a transactional index-health record gates readiness and retrieval, and a dedicated scheduler actor coordinates bounded refresh work.

**Tech Stack:** Swift 6, Swift Concurrency actors/task groups, Swift Testing, SQLite/FTS5, existing macOS connector protocols and SwiftUI source views.

---

### Task 1: Model verified index health and remove optimistic readiness

**Files:**
- Create: `Sources/MacBrain/Models/ConnectorIndexHealth.swift`
- Modify: `Sources/MacBrain/Models/SourceConnector.swift`
- Create: `Tests/MacBrainTests/ConnectorIndexHealthTests.swift`

- [ ] **Step 1: Write failing domain tests**

```swift
import Foundation
import Testing
@testable import MacBrain

struct ConnectorIndexHealthTests {
    @Test func newConnectorIsNotReady() {
        let record = ConnectorRecord(
            kind: .appleNotes,
            displayName: "Apple Notes",
            configuration: .init()
        )
        #expect(record.status == .syncing)
    }

    @Test(arguments: [0, 18])
    func verifiedInitialIndexIsSearchable(documentCount: Int) {
        let health = ConnectorIndexHealth(
            sourceID: UUID(),
            documentCount: documentCount,
            chunkCount: documentCount,
            contentRevision: "revision-1",
            initialSyncCompleted: true,
            lastSuccessfulSync: .now,
            lastVerifiedAt: .now
        )
        #expect(health.isSearchable)
        #expect(health.isEmpty == (documentCount == 0))
    }

    @Test func unverifiedIndexIsNotSearchable() {
        let health = ConnectorIndexHealth(sourceID: UUID())
        #expect(!health.isSearchable)
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache \
  swift test --filter ConnectorIndexHealthTests
```

Expected: compilation fails because `ConnectorIndexHealth` does not exist and the current record default is `.ready`.

- [ ] **Step 3: Add the domain model and safe default**

```swift
import Foundation

struct ConnectorIndexHealth: Codable, Equatable, Sendable {
    let sourceID: UUID
    var documentCount: Int
    var chunkCount: Int
    var contentRevision: String
    var initialSyncCompleted: Bool
    var lastSuccessfulSync: Date?
    var lastVerifiedAt: Date?
    var lastError: String?

    init(
        sourceID: UUID,
        documentCount: Int = 0,
        chunkCount: Int = 0,
        contentRevision: String = "",
        initialSyncCompleted: Bool = false,
        lastSuccessfulSync: Date? = nil,
        lastVerifiedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.sourceID = sourceID
        self.documentCount = documentCount
        self.chunkCount = chunkCount
        self.contentRevision = contentRevision
        self.initialSyncCompleted = initialSyncCompleted
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastVerifiedAt = lastVerifiedAt
        self.lastError = lastError
    }

    var isSearchable: Bool { initialSyncCompleted && lastVerifiedAt != nil }
    var isEmpty: Bool { isSearchable && documentCount == 0 }
}
```

Change the `ConnectorRecord` initializer default to `status: ConnectorStatus = .syncing`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: all three tests pass.

### Task 2: Persist index health and application metadata in SQLite

**Files:**
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Modify: `Tests/MacBrainTests/MacBrainDatabaseTests.swift`

- [ ] **Step 1: Write failing migration and round-trip tests**

Add Swift Testing coverage that creates a fresh database, asserts schema version 11, saves a `ConnectorIndexHealth`, reopens the database, and compares every field. Also save/read `legacy_source_import_complete = true` through metadata APIs.

```swift
@Test func indexHealthAndMetadataRoundTrip() async throws {
    let database = try MacBrainDatabase(url: try temporaryDatabaseURL())
    let sourceID = UUID()
    let record = ConnectorRecord(id: sourceID, kind: .appleNotes, displayName: "Notes", configuration: .init())
    try await database.save(connectorRecord: record)
    let health = ConnectorIndexHealth(
        sourceID: sourceID,
        documentCount: 18,
        chunkCount: 24,
        contentRevision: "notes-r1",
        initialSyncCompleted: true,
        lastSuccessfulSync: .now,
        lastVerifiedAt: .now
    )
    try await database.save(indexHealth: health)
    try await database.setMetadata("legacy_source_import_complete", value: "true")
    #expect(try await database.indexHealth(sourceID: sourceID) == health)
    #expect(try await database.metadata("legacy_source_import_complete") == "true")
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'MacBrainDatabaseTests|ConnectorIndexHealthTests'`

Expected: missing index-health and metadata APIs.

- [ ] **Step 3: Add migration 11 and typed APIs**

Increment `currentSchemaVersion` to 11 and add:

```sql
CREATE TABLE IF NOT EXISTS source_index_state (
    source_id TEXT PRIMARY KEY NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    document_count INTEGER NOT NULL,
    chunk_count INTEGER NOT NULL,
    content_revision TEXT NOT NULL,
    initial_sync_completed INTEGER NOT NULL,
    last_successful_sync REAL,
    last_verified_at REAL,
    last_error TEXT
);
CREATE TABLE IF NOT EXISTS app_metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);
```

Implement these actor methods:

```swift
func save(indexHealth: ConnectorIndexHealth) throws
func indexHealth(sourceID: UUID) throws -> ConnectorIndexHealth?
func allIndexHealth() throws -> [UUID: ConnectorIndexHealth]
func setMetadata(_ key: String, value: String) throws
func metadata(_ key: String) throws -> String?
```

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: migration and round-trip tests pass.

### Task 3: Commit documents, FTS, connector state, and health atomically

**Files:**
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Create: `Tests/MacBrainTests/SourceIndexCommitTests.swift`

- [ ] **Step 1: Write failing atomic-commit tests**

Test a successful source-generation replacement, an empty verified generation, and an injected failure after document insertion. The failed transaction must retain the previous document, FTS match, connector record, and health revision.

```swift
@Test func failedGenerationKeepsPreviousVerifiedIndex() async throws {
    let fixture = try await SourceCommitFixture.make()
    try await fixture.commit(marker: "OLD-VERIFIED", revision: "r1")
    await #expect(throws: MacBrainDatabaseError.injectedFailure) {
        try await fixture.commit(marker: "NEW-UNCOMMITTED", revision: "r2", failAfterDocuments: true)
    }
    #expect(try await fixture.matches("OLD-VERIFIED").count == 1)
    #expect(try await fixture.matches("NEW-UNCOMMITTED").isEmpty)
    #expect(try await fixture.database.indexHealth(sourceID: fixture.sourceID)?.contentRevision == "r1")
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SourceIndexCommitTests`

Expected: the transactional source-generation API is missing.

- [ ] **Step 3: Implement one transactional commit boundary**

Add:

```swift
enum SourceGenerationFailurePoint: Sendable {
    case afterDocuments
}

func commitSourceGeneration(
    record: ConnectorRecord,
    documents: [StoredDocument],
    health: ConnectorIndexHealth,
    failurePoint: SourceGenerationFailurePoint? = nil
) throws -> ConnectorIndexHealth
```

Inside one `connection.transaction`, replace changed/removed documents and their chunks/FTS rows, save the connector record, count committed documents and chunks, update `source_index_state`, and validate that every live chunk has one FTS row. Return counts read from the committed transaction. Do not mutate the caller-visible record to ready before this method succeeds.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: all atomicity cases pass.

### Task 4: Bootstrap, import, and repair legacy source state

**Files:**
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Create: `Tests/MacBrainTests/LocalSourceBootstrapTests.swift`

- [ ] **Step 1: Reproduce the split-store bug**

Create a legacy snapshot containing one ready Apple Notes record and 18 normalized documents, use an empty SQLite database, then bootstrap. Assert the SQLite count and FTS search both become 18/searchable without changing the incoming connector data.

Also reproduce the unchanged-sync repair: delete SQLite documents after a successful import, call `replaceDocuments` with the identical incoming documents, and expect the index to be rebuilt.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter LocalSourceBootstrapTests`

Expected: SQLite stays empty because unchanged snapshot data returns early.

- [ ] **Step 3: Add idempotent repository bootstrap**

Implement:

```swift
func bootstrap() async throws
func indexHealth(for connectorID: UUID) async -> ConnectorIndexHealth?
func sourceHealth() async -> [UUID: ConnectorIndexHealth]
```

Bootstrap must migrate SQLite, import the decoded schema-2 snapshot only when the metadata marker is absent, rebuild any source whose SQLite count/FTS integrity disagrees with its legacy snapshot, hydrate repository state from SQLite, mark orphan source IDs ineligible, and set the marker only after all source imports verify.

When a database is configured, compare incoming documents with SQLite rather than returning solely from the legacy in-memory comparison. Stop persisting production runtime documents to JSON after bootstrap. Preserve JSON-only behavior for explicitly constructed database-free test repositories.

- [ ] **Step 4: Run repair tests and restart tests**

Run: `swift test --filter 'LocalSourceBootstrapTests|MacBrainDatabaseTests'`

Expected: split-store, unchanged repair, idempotent second bootstrap, and restart cases pass.

### Task 5: Gate lifecycle readiness on verified commits

**Files:**
- Modify: `Sources/MacBrain/Services/LocalSourceCoordinator.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Modify: `Sources/MacBrain/Stores/SourceLibraryStore.swift`
- Create: `Tests/MacBrainTests/ConnectorLifecycleTests.swift`

- [ ] **Step 1: Write fresh-connect and interrupted-sync failures**

Use a controlled connector that blocks before returning documents. Assert create/connect publishes `.syncing`, never `.ready`; resolving the connector commits searchable FTS before `.ready`; zero documents produce verified empty-ready; and `recoverInterruptedSyncs` verifies/restarts rather than assigning ready.

```swift
@Test @MainActor func connectBecomesReadyOnlyAfterSearchableCommit() async throws {
    let fixture = try await ConnectorLifecycleFixture.make()
    fixture.store.addAndSync(kind: .appleNotes, displayName: "Notes", configuration: .init())
    await fixture.connector.waitUntilStarted()
    #expect(fixture.store.records.first?.status == .syncing)
    await fixture.connector.finish(with: [fixture.note])
    await fixture.store.waitUntilIdle()
    #expect(fixture.store.records.first?.status == .ready)
    #expect((await fixture.repository.searchLexicalEvidence("ORBIT-READY")).evidence.count == 1)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ConnectorLifecycleTests`

Expected: records start ready and interrupted sync is optimistically recovered.

- [ ] **Step 3: Route every connector through verified commit**

Update nonbatched, file-backed, and batched sync paths to build a `ConnectorIndexHealth`, call the repository transactional commit/verification boundary, and only then save `.ready`. Keep the last verified health during refresh failure. Replace optimistic interrupted-sync recovery with repository verification followed by safe resume/restart.

Initial sync must enqueue changed chunks after the lexical commit. `addAndSync`, Browser Profiles, manual sync, resume, and authorization retry must share this coordinator path.

- [ ] **Step 4: Run and verify GREEN**

Run: `swift test --filter 'ConnectorLifecycleTests|SourceConnectorTests|MacBrainDatabaseTests'`

Expected: all lifecycle variants pass, including empty libraries and restart.

### Task 6: Add a cancellable bounded five-minute scheduler

**Files:**
- Create: `Sources/MacBrain/Services/ConnectorRefreshScheduler.swift`
- Modify: `Sources/MacBrain/Stores/SourceLibraryStore.swift`
- Modify: `Sources/MacBrain/App/AppCoordinator.swift`
- Create: `Tests/MacBrainTests/ConnectorRefreshSchedulerTests.swift`

- [ ] **Step 1: Write deterministic scheduler tests**

Define an injected sleeper/clock and controlled refresh operation. Cover exactly 300 seconds, due filtering, maximum concurrency, per-source coalescing, failure isolation, cancellation, and shutdown without using wall-clock sleeps.

```swift
protocol ConnectorRefreshClock: Sendable {
    func sleep(for duration: Duration) async throws
    func now() async -> Date
}

@Test func refreshesDueSourcesConcurrentlyAndCoalescesDuplicates() async throws {
    let probe = RefreshProbe()
    let scheduler = ConnectorRefreshScheduler(
        interval: .seconds(300),
        maximumConcurrentRefreshes: 3,
        clock: ManualConnectorRefreshClock(),
        loadCandidates: { probe.candidates },
        refresh: { await probe.refresh($0) }
    )
    await scheduler.runDueRefresh()
    #expect(await probe.maximumConcurrency() == 3)
    #expect(await probe.refreshCount(for: probe.candidates[0].id) == 1)
}
```

The test target provides a `ManualConnectorRefreshClock` actor whose `sleep(for:)` stores checked continuations and whose `advance(by:)` resumes only deadlines reached by the advanced logical time. This makes the 300-second boundary and cancellation deterministic without wall-clock sleeps.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ConnectorRefreshSchedulerTests`

Expected: scheduler types are missing.

- [ ] **Step 3: Implement the actor**

Use one lifecycle-owned loop task, cancellation-aware `Clock.sleep`, an in-flight source-ID set, and a bounded task group that adds another source only when one child completes. Return per-source outcomes instead of throwing the whole group. Expose next-run time and events through `AsyncStream` or injected `@MainActor` sinks.

- [ ] **Step 4: Integrate scheduler ownership**

`AppCoordinator.start` must await repository bootstrap before starting the scheduler. `stop` cancels and awaits scheduler shutdown. `SourceLibraryStore` consumes progress events and never performs scanning, hashing, or database work on the main actor.

- [ ] **Step 5: Run and verify GREEN**

Run: `swift test --filter 'ConnectorRefreshSchedulerTests|ConnectorLifecycleTests|SourceConnectorTests'`

Expected: deterministic scheduling and existing refresh behavior pass.

### Task 7: Make capability and Source Manager readiness truthful

**Files:**
- Modify: `Sources/MacBrain/Services/LocalSourceCapabilityResponder.swift`
- Modify: `Sources/MacBrain/Views/SourceManagerView.swift`
- Modify: `Tests/MacBrainTests/LocalSourceCapabilityResponderTests.swift`
- Create: `Tests/MacBrainTests/SourcePresentationStateTests.swift`

- [ ] **Step 1: Write failing split-state and empty-state tests**

Assert a `.ready` record with unverified/zero SQLite health is described as not yet searchable, a verified zero-document source is described as connected but empty, a verified nonempty source is ready, and a background refresh keeps the ready index available.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'LocalSourceCapabilityResponderTests|SourcePresentationStateTests'`

Expected: the capability responder trusts record status alone.

- [ ] **Step 3: Render one derived presentation state**

Create a pure mapping from `(ConnectorRecord, ConnectorIndexHealth?)` to connecting, syncing, ready, empty, paused, permission-needed, or failed-with-retained-index. Feed this mapping to both capability responses and Source Manager cards. Never display “ready to search” without verified health.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: all truthful-state cases pass.

### Task 8: Verify the complete connector core

**Files:**
- Modify: `Tests/StressTests/production_chat_acceptance_audit.md`

- [ ] **Step 1: Run focused core tests**

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache \
  swift test --filter 'ConnectorIndexHealthTests|SourceIndexCommitTests|LocalSourceBootstrapTests|ConnectorLifecycleTests|ConnectorRefreshSchedulerTests|SourcePresentationStateTests|SourceConnectorTests|MacBrainDatabaseTests'
```

Expected: zero failures.

- [ ] **Step 2: Run the full deterministic suite**

Run: `swift test`

Expected: zero failures; opt-in live Ollama tests skip unless enabled.

- [ ] **Step 3: Run focused Thread Sanitizer verification**

Run:

```sh
swift test --sanitize=thread --filter 'ConnectorLifecycleTests|ConnectorRefreshSchedulerTests'
```

Expected: zero test failures and no data-race reports.

- [ ] **Step 4: Record evidence**

Add exact commands/results for fresh connect, split-store repair, verified readiness, five-minute scheduling, concurrency, cancellation, and no-source-edit acceptance. Do not claim real Apple permission behavior from synthetic connectors.
