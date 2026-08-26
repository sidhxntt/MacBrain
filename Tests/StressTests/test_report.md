# MacBrain Test Report

Date: 2026-08-26

## Delegated acceptance-linked regressions

Each sub-agent ran one distinct test.

| Sub-agent | Test | Result |
| --- | --- | --- |
| `citation_acceptance` | `HybridEvidenceRetrieverTests/testCitationValidatorOnlyRendersKnownCitationIDs` | Pass — 1 test, 0 failures |
| `database_acceptance` | `MacBrainDatabaseTests/testDocumentWriteIsAtomicAndProvidesFTSAndVectorSearch` | Pass — 1 test, 0 failures |
| `streaming_acceptance` | `StreamingChatResponderTests/testCancellingGroundedResponsePreservesDirectEvidence` | Pass — 1 test, 0 failures |

## Full automated suite

Command:

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/notchbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/notchbrain-swiftpm-cache swift test
```

Result: **177 tests executed, 0 failures; 2 were skipped.** The skipped tests are live-Ollama checks that require `MACBRAIN_LIVE_OLLAMA=1`.

## Live-Ollama integration

Verified local prerequisites: `qwen3:8b` and `nomic-embed-text:latest` are installed and available through the local Ollama service.

Command:

```sh
env MACBRAIN_LIVE_OLLAMA=1 \
  CLANG_MODULE_CACHE_PATH=/tmp/notchbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/notchbrain-swiftpm-cache \
  swift test --filter 'MacBrainTests.OllamaLiveIntegrationTests'
```

Result: **2 tests passed, 0 failures.**

## Outcome

With live Ollama enabled, the full suite completed with **177 tests executed, 0 failures, and 0 skips**. No fixes or source changes were required.

The manual full-app acceptance cards A01–A29 in `acceptance_tests.md` require interactive macOS UI actions (and, for some cards, explicit permission decisions); they are not represented as runnable automated tests in the package.

## Connector reliability regression — 2026-08-26

Command:

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/notchbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/notchbrain-swiftpm-cache swift test
```

Result: **198 tests executed, 0 failures; 2 live-Ollama tests skipped.**

Automated connector stress coverage now verifies:

- all 11 connector kinds start a due refresh concurrently;
- a non-cooperative connector reaches `.failed` at the configured deadline (production: two minutes);
- cache-stable snapshot resyncs enqueue no new index jobs, while changed records enqueue only changed chunks;
- batched connectors refresh the final search index and queue changed chunks once after the last batch;
- folder, Git, browser-profile, Apple-library, and EventKit connector regressions remain green in `SourceConnectorTests`.

Live connector authorization and personal-data verification remain intentionally manual and must be marked **not tested** when macOS permission is unavailable.
