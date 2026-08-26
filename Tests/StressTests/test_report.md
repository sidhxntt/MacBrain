# MacBrain Test Report

Date: 2026-08-26

## Current-tree outcome

The deterministic connector, query, system, onboarding, and persistence suites pass on the current worktree. Coverage includes a fresh-install connect → immediate verified sync → natural question → structured count → restart journey with zero source mutation, plus all 11 connector kinds across 198 adversarial cases.

Real Apple permission prompts and personal source answers were not exercised automatically. The current-tree local Ollama suite passed with controlled synthetic content; answer-path telemetry distinguishes model-authored output from MacBrain's verified-evidence fallback. A metadata-only production run also verified migration, restart, the five-minute scheduler, and index health without inspecting personal document bodies.

## Verification evidence

### Focused connector core

```sh
swift test --filter 'ConnectorIndexHealthTests|SourceIndexCommitTests|LocalSourceBootstrapTests|ConnectorLifecycleTests|ConnectorRefreshSchedulerTests|SourcePresentationStateTests|SourceConnectorTests|MacBrainDatabaseTests|SourceAccessRetrievalTests'
```

Result: 81 XCTest cases and 40 Swift Testing cases passed with zero failures. This includes atomic verified generations, verified empty sources, split-store repair, SQLite-only restart authority, stale-JSON resurrection prevention, five-minute scheduling, bounded concurrency, shared-sync coalescing, cancellation, crash-safe batched recovery, permission revocation isolation, deletion, and all connector adapters.

### Focused query behavior

```sh
swift test --filter 'LocalQueryPlannerTests|ConnectorStructuredQueryTests|ConnectorQueryServiceTests|LexicalFirstRetrievalTests|QueryPlanResponderTests|SystemQueryServiceTests|ResponseCachingResponderTests'
```

Result: 30 XCTest cases and 17 Swift Testing cases passed with zero failures. Natural questions, authoritative counts and dates, capability questions, lexical-first fallback, unavailable-model behavior, system facts, cache invalidation, and public/local separation passed.

### Photos index-count regression

```sh
swift test --filter 'LocalQueryPlannerTests|QueryPlanResponderTests|ConnectorQueryServiceTests'
```

Result: 9 XCTest cases and 16 Swift Testing cases passed with zero failures. The exact prompt `How many photos do I have indexed?` resolves to a structured Photos count, returns exactly the verified two-photo fixture count without calling the inference provider or rendering source evidence, and retains that two-photo count while an uncommitted three-photo refresh is present. A public Photos-framework count question remains unscoped.

### Fresh-install and adversarial acceptance

```sh
swift test --filter 'FreshInstallConnectorE2ETests|FreshInstallSystemE2ETests|ConnectorAdversarialE2ETests|SourceLibraryStoreInitialSyncTests|ConnectorLifecycleTests|ConnectorRefreshSchedulerTests|LocalSourceBootstrapTests'
```

Result: 24 Swift Testing cases in 7 suites passed. The adversarial parameterized case exercised 198 connector prompts. Initial connect also drained queued enrichment after the verified lexical commit.

```sh
swift test --filter 'ConnectorAdversarialE2ETests|SourceAccessRetrievalTests|ProductionPromptBarrageTests'
```

Result: 2 XCTest cases and 10 Swift Testing cases passed; the connector matrix again completed all 198 parameterized cases with no unauthorized, unverified, stale, or cross-source disclosure.

### Complete deterministic suite

```sh
swift test --quiet
```

Result: XCTest executed 280 tests with 0 failures and 6 explicit opt-in live-test skips in 14.142 seconds. Swift Testing executed 94 tests in 20 suites with 0 failures in 3.492 seconds.

### Thread Sanitizer

```sh
swift test --sanitize=thread --filter 'ConnectorLifecycleTests|LocalSourceBootstrapTests|SourceIndexCommitTests'
```

Result: 22 Swift Testing cases in 3 suites passed with no Thread Sanitizer warning or reported race.

### Release and packaged app

```sh
swift build -c release
./script/build_and_run.sh --verify
```

Result: the release product built successfully. The app bundle was rebuilt, re-signed, launched, and the process check printed `MacBrain launched successfully`.

Latest local rerun: the Swift build and bundle signing completed, but sandboxed Launch Services returned `kLSNoExecutableErr`; an elevated launch verification did not complete before its process check. The new Photos-count behavior is therefore verified through the production responder with controlled SQLite records, not through a live personal-library UI session in this environment.

### Live Ollama

```sh
env MACBRAIN_LIVE_OLLAMA=1 \
  CLANG_MODULE_CACHE_PATH=/private/tmp/macbrain-live-clang-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/macbrain-live-swiftpm-cache \
  swift test --filter OllamaLiveIntegrationTests
```

Result: 5 tests passed with zero failures in 76.094 seconds. All 66 connector/dimension cases and all 16 production-soak prompts completed. The connector matrix recorded 47 model-authored answers, 8 verified-evidence fallbacks, and 11 deterministic permission-state answers; every final response passed the controlled fact, citation, freshness, permission, and isolation assertions.

### Production database and scheduler

The packaged app migrated the existing database to schema 13 and verified all 17 connected records. A one-time large-folder repair committed 21,136 documents and 384,849 chunks without hydrating the full source into repository memory. The exact final bundle began its automatic cycle at 21:46:56 after the five-minute wait and completed all sources by 21:53:46. During that run, the large folder scanned 21,136 present documents in 2.2 seconds and submitted only three changed documents; an unchanged 998-document folder completed its database reconciliation in under one second. Previous verified indexes remained queryable while refreshes ran.

After rebuilding the current bundle, the same database relaunched with all 17 sources ready and verified, zero duplicate name/kind groups, and exactly one Safari record. The process settled at 0% CPU and approximately 165 MB RSS without creating or modifying any source item. These checks queried connector status, counts, and health only; no personal document body was inspected.

## Defects reproduced and fixed

- Bootstrap continued treating `local-sources.json` as an authorization filter after migration. A missing file hid valid SQLite connectors, while a stale file could resurrect a deleted connector. The migration marker now makes SQLite the only runtime authority and post-bootstrap writes no longer update JSON.
- A second manual or automatic sync returned the stale `.syncing` record instead of waiting. Per-source callers now coalesce and receive the same committed result or error; a cancelled waiter does not cancel the shared owner.
- Cancelling a sync did not cancel detached scanning, allowing cancelled content to commit. Cancellation now reaches the worker and timeout race, and a cancelled initial sync cannot publish a verified generation.
- Normal `addAndSync` queued enrichment but did not drain it. Initial connection now processes configured enrichment after the durable lexical generation is searchable.
- The live Ollama harness inserted documents without a verified index generation, making its first current-tree matrix run correctly return no evidence. Live fixtures now commit the same ready record/document generation used by production before querying.
- Ready status previously existed independently from index integrity. Retrieval and presentation now require verified SQLite health; verified empty sources remain valid and distinct.
- Connector questions could bypass lexical retrieval when Ollama was unavailable. Accepted lexical evidence now returns a bounded cited answer without requiring chat or embedding models.
- Generic phrasing, structured count/date questions, and natural uptime wording had routing gaps. One planner now separates capability, connector, system, restricted, casual, and evidence plans.
- Revoked or deleted content could previously remain reachable through alternate retrieval or cache paths. Eligibility is enforced before every query path and committed access/content revisions invalidate cached answers.
- Startup previously decoded the entire SQLite document corpus into memory, including a roughly 500 MiB folder, before the app could recover connector state. SQLite now remains the live document authority and source bodies load only when a specific operation needs them.
- Large file-backed refreshes previously materialized every unchanged document and performed quadratic chunk line-number and unindexed deletion work. Reconciliation now sends changed documents plus present IDs, chunks calculate line ranges in linear time, prepared statements are reused, and schema 13 indexes `chunks.document_id`.
- A crash between pages of Mail, Messages, or Photos could leave a persisted offset pointing beyond pages held only in process memory. Interrupted batched generations now clear that offset and restart from page zero before any new generation is committed.

## Scope boundary

The deterministic tests use controlled connector records and temporary SQLite databases; they do not read personal Notes, Mail, Calendar, Reminders, Contacts, Messages, Photos, Books, browser, folder, or Git content. Adapter tests cover normalization and permission-error handling, but the real macOS permission dialogs, return-from-Settings behavior, and answers against the user's existing data require the manual questions in `question-to-ask.md`.
