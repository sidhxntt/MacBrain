# Reliable Connectors, Open-Ended Queries, and First-Run Experience

**Date:** 2026-08-26

## Goal

Make the installed MacBrain experience reliable from first launch: the user connects a source once, MacBrain immediately performs an initial sync without requiring the user to edit source content, marks the source ready only after the same local index used by chat is verified, refreshes connected sources every five minutes without blocking the UI, answers naturally worded questions about authorized sources, and answers read-only questions about the current Mac.

## Scope and product contract

This design covers all eleven existing connector kinds: Apple Notes, Apple Mail, Calendar, Reminders, Contacts, Browser Profiles, Messages, Photos metadata, Apple Books, Folder, and Git repository.

The product contract is:

1. A fresh install explains local processing and lets the user connect individual sources.
2. Connecting starts the initial sync immediately after authorization. No source edit, marker insertion, or second manual sync is required.
3. Source content becomes searchable as soon as its durable lexical index is committed. Embeddings enrich retrieval later and never block initial searchability.
4. “Ready” means authorization succeeded, the initial scan completed, and SQLite document/chunk/FTS state was verified. A connected empty source is a valid, explicitly empty ready state.
5. While MacBrain is open, due sources refresh every 300 seconds. Independent sources run concurrently with bounded parallelism, per-source duplicate suppression, cancellation, and failure isolation.
6. The last verified index remains queryable during a background refresh. A failed refresh does not destroy previously verified authorized data.
7. Paused sources retain their verified index but do not refresh. Authorization-revoked and deleted sources are never queryable.
8. Natural questions do not need a fixed prefix such as “search my notes.” Explicit source wording narrows the search; it does not determine whether search is attempted.
9. Counts, newest/oldest records, and date-ordered connector questions use structured SQLite queries. Factual content questions use lexical retrieval first and optional semantic/graph enrichment.
10. Read-only system questions use a freshly sampled Mac snapshot. MacBrain does not quit apps, modify settings, delete data, or otherwise control the Mac in this scope.
11. The app can recover from interrupted syncs, a missing index, legacy JSON/SQLite disagreement, and application restart without asking the user to modify source content.
12. Removed sources, denied permissions, privacy-restricted requests, and stale cache entries cannot expose source content.

## Current-state failures being replaced

The current implementation violates the contract in several concrete ways:

- `ConnectorRecord` defaults to `.ready` before any scan or index verification.
- `LocalSourceCapabilityResponder` trusts that status instead of the searchable database.
- `LocalSourceRepository` maintains a large JSON document snapshot as well as SQLite. An unchanged connector result returns before repairing a missing SQLite index.
- Chat searches SQLite when it exists, so JSON can report documents that chat cannot retrieve.
- Interrupted `.syncing` records are reset to `.ready` without verifying the index.
- General prompts do not attempt local retrieval. Only a finite phrase list activates explicit or implicit local routing.
- Hybrid retrieval has a fixed three-second race whose timeout resolves to an empty result, even when lexical evidence exists.
- Free-text RAG is used for operations such as counts that require deterministic database queries.
- Initial `addAndSync` does not consistently drain enrichment jobs, while browser setup follows a separate path.
- The existing test matrix proves controlled seeded retrieval but not the real fresh-install `connect -> sync -> index -> ask` lifecycle.

## Architecture decision

Use an incremental Clean Architecture boundary for connector and query behavior while preserving the existing SwiftUI views and MVVM-style `SourceLibraryStore`. No third-party framework is added.

- **Domain:** connector lifecycle/searchability, sync requests and results, query plans, structured results, and system capabilities.
- **Application services:** initial-sync use case, refresh scheduler, startup reconciliation, local query planner, connector query executor, and system query executor.
- **Data adapters:** existing macOS connectors and a SQLite-backed local source repository.
- **Presentation:** `SourceLibraryStore`, onboarding state, Source Manager, and chat streaming render domain state but do not decide persistence or retrieval rules.
- **Composition root:** `AppCoordinator` constructs one migrated `MacBrainDatabase`, one repository, one sync engine, one scheduler, and one query service shared by source management and chat.

This is a focused migration rather than a full rewrite. Existing connector adapters, chunking, citations, Ollama provider, chat UI, and source UI remain in place unless their boundary must change for correctness.

## Authoritative persistence and migration

SQLite becomes the only authoritative runtime store for connector records, normalized documents, chunks, FTS rows, embeddings, and index health.

Add a database migration containing a `source_index_state` table keyed by `source_id` with:

- lifecycle/searchability state;
- committed document and chunk counts;
- content revision;
- initial-sync-completed flag;
- last successful scan and last verified index timestamps;
- last refresh error without private source content.

Document/chunk/FTS mutations and the corresponding index-state update occur in one SQLite transaction. A record may transition to ready only after that transaction commits and a verification query confirms the committed counts and FTS integrity.

`local-sources.json` is retained only as legacy migration input. On bootstrap:

1. migrate the SQLite schema;
2. if the legacy import marker is absent, import connector records and documents missing from SQLite in source-sized transactions;
3. compare the authoritative SQLite document/chunk counts with the legacy snapshot for every active record;
4. rebuild a missing or inconsistent SQLite source index from the snapshot when safe;
5. verify the rebuilt index, update `source_index_state`, and persist the import marker in SQLite's settings table;
6. stop writing new runtime state to the JSON file.

The legacy file is not deleted automatically in this change. It is ignored after a successful import, preventing two active sources of truth while preserving a recovery artifact during beta migration.

Startup marks orphan SQLite sources ineligible when they have no active connector record and are not part of a pending legacy import. Their rows are retained for safe beta recovery until the user explicitly removes them; they cannot influence search or consume retrieval time.

## Connector lifecycle

Use explicit lifecycle state rather than treating “connected” and “searchable” as synonyms:

```text
not connected
  -> authorizing
  -> initial sync
  -> committing lexical index
  -> verified ready (records may be empty)
  -> background refresh -> verified ready

authorization failure -> permission needed
scan/index failure     -> failed, with last verified index retained when authorized
user pause             -> paused, verified index retained
user delete            -> configuration and complete index removed atomically
```

The connector record must not default to ready. New records begin in the initial-sync state. `SourceLibraryStore` renders connector state returned by the repository; it does not synthesize ready locally.

Initial sync flow:

1. Save the user-confirmed connector configuration.
2. Start sync immediately in a child task owned by the source feature.
3. Scan off the main actor through the connector protocol.
4. Commit normalized documents, chunks, FTS rows, record state, and index health atomically.
5. Verify database counts/searchability.
6. Publish ready or empty-ready state to the UI.
7. Enqueue embedding and graph enrichment for changed chunks. These jobs are cancellable and do not gate lexical search.

For batched connectors, each committed batch may become searchable, but the connector is not labeled fully ready until the terminal batch and verification complete. Progress is durable. Restart resumes or safely restarts incomplete initial sync; it never guesses readiness.

## Five-minute refresh and concurrency

Introduce a `ConnectorRefreshScheduler` actor with an injected clock and a fixed production interval of 300 seconds.

- It starts after repository bootstrap and stops during application termination.
- It schedules from each connector’s last successful scan, so relaunch does not create unnecessary immediate work.
- It uses a throwing/discarding task group with bounded parallelism instead of one unbounded `Task` per source.
- It maintains one in-flight operation per source. Manual sync coalesces with an active automatic sync instead of duplicating it.
- Cancellation propagates to connector scanning, batch iteration, indexing, and scheduler shutdown.
- A source failure is recorded for that source only and cannot cancel unrelated source refreshes.
- The UI receives small main-actor state updates; scanning, database writes, hashing, chunking, and enrichment remain actor-isolated off the main actor.
- Background refresh builds and commits a source generation atomically, so chat reads either the last verified generation or the new verified generation, never a half-written mix.

The existing sync-activity UI remains useful, but background refresh does not change a searchable connector to an ineligible state. Availability and refresh activity are separate concepts.

## Query planning and execution

Replace phrase-gated retrieval with a query plan and two local-data paths.

### Planning order

1. Apply privacy/restricted-request policy.
2. Detect a live or static local-system question.
3. Detect a connector capability/status question.
4. Detect a structured connector operation.
5. For every remaining non-casual prompt, perform a cheap bounded lexical search across authorized searchable sources.
6. If explicit connector names or source aliases are present, restrict every local query path to those kinds.
7. Apply evidence acceptance. Strong lexical evidence activates grounded answering; weak or absent evidence falls through to ordinary local-model chat.
8. Optionally enrich accepted lexical evidence with semantic and graph candidates within a separate budget.

Source aliases are maintained in one `SourceVocabulary` derived from connector kind names, record display names, and a compact synonym set. They narrow scope only. The system no longer relies on a growing list of complete question phrases.

### Structured connector operations

Add `ConnectorQueryService` backed by SQLite for operations that must be deterministic:

- count all records or records within one or more named connector kinds;
- list newest/oldest records by normalized creation or modification date;
- return the next event or first due incomplete reminder when the connector metadata supports it;
- list matching records with stable limits and source provenance;
- report connector/index health and the time of the last verified sync.

The query planner recognizes operation intent independently from source scope. “How many notes do I have?”, “What is my note count?”, and equivalent count wording all produce the same count plan. Results are rendered directly with the authoritative count and do not ask the model to calculate it.

### Evidence retrieval

Lexical retrieval runs first and is always preserved. Semantic retrieval is optional enrichment:

```text
lexical FTS result
  + semantic candidates if embeddings finish within budget
  + graph candidates if available
  -> fusion, authorization filter, source diversity, evidence acceptance
```

A semantic timeout cancels only semantic work and returns lexical evidence. It cannot turn a valid lexical result into empty evidence. Explicitly named authorized sources with no match receive a truthful no-match response; generic prompts with no accepted evidence continue as general chat.

Eligibility is computed from authoritative index health. Deleted and authorization-needed sources are excluded before FTS, vector, graph, fallback, and structured queries. Paused sources may remain searchable because the user has not revoked access; their response states that freshness is paused.

Response-cache revisions come from the committed SQLite content revision and access state. A sync, authorization change, pause/delete, or migration repair invalidates affected cached answers.

## Read-only Mac and OS questions

System support is informational and diagnostic. It does not perform external actions.

Expand the current live-system boundary into a `SystemQueryService` that samples requested facts per query and returns typed values with capture time. Supported domains include:

- identity, Mac name/model, architecture, processor brand, physical/logical CPU counts, and installed memory;
- current memory counters and swap where available;
- total/used/available storage for mounted local volumes;
- macOS version, uptime, boot time, locale, and time zone;
- CPU load;
- battery percentage, charging source, and available health/cycle information;
- active/running applications;
- active network interfaces without exposing credentials;
- connected displays and their reported resolution when available.

Direct factual questions receive deterministic answers from the sampled values. Broader questions such as “Explain my Mac specifications” receive a structured, freshly sampled system context for local-model synthesis. General educational questions about macOS remain normal model questions. Every dynamic query bypasses the response cache.

“Maximum specification” is interpreted as the maximum or installed capacity the operating system can truthfully report for the requested component. MacBrain must say when macOS does not expose a supported maximum rather than inventing a product limit.

## First-run onboarding and source UI

Add a first-run onboarding sheet before the normal workspace becomes the primary experience. Completion is stored in app preferences and the flow can be reopened from Settings.

The onboarding has four focused steps:

1. **What MacBrain is:** a local assistant that searches only sources the user chooses; source content and local inference remain on the Mac.
2. **Local AI readiness:** show Ollama/model status and reuse the existing setup surface.
3. **Connect sources:** reuse connector descriptions and connection actions, explain each macOS permission before invoking it, allow individual connection, and show initial-sync/index progress without displaying private content.
4. **Ready to ask:** show which sources are verified searchable, which are empty/optional/need permission, the five-minute refresh promise, and example connector/system questions based only on actually available capabilities.

The user may continue with limited context and return later. Folder and Git selection remain explicit. Full Disk Access guidance is shown only for connectors that need it. Source cards use truthful states: connecting, syncing, ready, ready-but-empty, paused, permission needed, and failed with retry guidance.

Capability answers in chat use the same index-health model as the UI. They can no longer say “ready to search” based only on a connector record flag.

## Error handling and recovery

- Permission denial transitions only that connector to permission-needed and excludes it from all query paths.
- An empty authorized library is ready-but-empty, not failed.
- Scan failure preserves the last verified authorized index and reports stale freshness.
- Index commit failure leaves the previous generation active and never publishes ready for the failed generation.
- Interrupted initial sync resumes when the connector supports durable paging; otherwise it restarts safely.
- Startup verification repairs missing FTS/chunks from authoritative documents or legacy migration input.
- Unavailable Ollama leaves structured queries, connector health, lexical evidence fallback, and deterministic system answers usable.
- Logs contain connector kind, phase, counts, duration, and error category, never prompt text or private document content.

## Testing and acceptance evidence

All new behavior follows red-green-refactor. New unit and integration tests use Swift Testing; UI automation remains XCTest when added.

Required deterministic coverage:

1. Fresh database and preferences -> connect a fake connector -> immediate scan -> committed FTS -> verified ready -> ask a naturally worded question without changing source content.
2. New record is never ready before successful index verification.
3. Legacy snapshot with documents and an empty SQLite source is repaired at startup; unchanged connector output also repairs the database.
4. SQLite and UI counts agree after initial sync, refresh, deletion, authorization change, and restart.
5. Empty Calendar/Books-style source becomes ready-but-empty.
6. Scheduler fires at 300 seconds using a controllable clock, refreshes independent sources concurrently within its limit, coalesces duplicate per-source work, propagates cancellation, and does not require timing sleeps.
7. One connector failure does not cancel another connector’s successful refresh.
8. Background refresh keeps the previous verified generation searchable until atomic commit.
9. Generic wording with a strong matching local record reaches retrieval; public/general wording with no accepted evidence does not inject unrelated local content.
10. Explicit source scope applies to lexical, semantic, graph, structured, and fallback paths.
11. “How many notes do I have?” returns the authoritative structured count.
12. Semantic timeout preserves lexical evidence.
13. Permission-needed and removed sources remain inaccessible; cache revisions change when access or content changes.
14. Current RAM, installed RAM, storage, processor/specification, macOS, battery, apps, network, uptime, and unsupported-maximum questions use fresh typed system facts.
15. Onboarding completion, skip/limited flow, reopen action, and truthful connector state rendering are covered at the state/view-model boundary.
16. Existing eleven-connector provenance, citation, freshness, permission, and cross-source isolation matrix remains green.

Required runtime acceptance on a clean or isolated app-data directory:

1. Launch MacBrain and complete/skip onboarding without a hang.
2. Connect at least one real Apple connector without editing its source data.
3. Observe immediate sync and verified ready/empty-ready state.
4. Ask a content question and a count question using natural wording.
5. Wait for or trigger the five-minute refresh while chatting; UI and token streaming remain responsive.
6. Restart and confirm the source remains searchable without an unnecessary reconnect.
7. Revoke permission and confirm source content is immediately unavailable.
8. Ask live RAM, storage, and specification questions and verify values against macOS.

Completion requires a clean build, the full deterministic test suite, focused Thread Sanitizer coverage for sync/query actors, migration verification with a split-store fixture, and an installed-app manual pass. Synthetic seeded retrieval alone is not sufficient evidence.

## Rollout order

1. Add SQLite index health, legacy migration, and startup repair.
2. Move lifecycle readiness to verified database state and unify immediate/manual/automatic sync.
3. Replace the refresh loop with the cancellable bounded scheduler.
4. Add structured connector queries and lexical-first open-ended retrieval.
5. Expand the read-only system query service.
6. Add onboarding and truthful source-state presentation.
7. Run migration, concurrency, full-suite, installed-app, and manual acceptance audits.

Each stage preserves a working app and introduces its failing acceptance tests before production changes.
