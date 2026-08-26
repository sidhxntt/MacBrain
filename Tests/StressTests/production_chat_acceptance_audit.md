# Production chat acceptance audit

Date: 2026-08-26

## Acceptance criteria

| Criterion | Verification evidence | Result |
|---|---|---|
| Every deterministic corpus case reaches its expected route and a terminal state | `ProductionPromptBarrageTests.testSeededProductionCorpusRoutesAndTerminatesWithoutLeakage` exercises 300+ seeded variants with per-request deadlines. | Pass |
| General and casual prompts perform no local retrieval or local-content disclosure | `testGeneralQuestionNeverEmbedsOrRendersMatchingLocalSources`, `testCasualGreetingBypassesUnrelatedLocalEvidence`, and collision documents in the production barrage. | Pass |
| Live Mac prompts use fresh providers, never indexed evidence | `testLiveMemoryQuestionReturnsSnapshotWithoutCallingInferenceProvider`, `testLiveStorageQuestionBypassesSourceSearchAndInference`, and the live-memory soak case. | Pass |
| Explicit local prompts retrieve connected data; implicit prompts require absolute lexical relevance | Direct-file and accepted-implicit responder tests, `EvidenceAcceptancePolicyTests`, and `testWeakImplicitLexicalCollisionDoesNotActivateHybridRetrieval`. | Pass |
| Weak or invented evidence never replaces a general answer or becomes an unbounded dump | Weak-collision, invented-citation, missing-citation, known-cited-subset, and cancellation responder tests. | Pass |
| Grounded follow-ups trust persisted routing metadata only | Router regression rejects citation-looking ungrounded text; ChatStore/database tests preserve source IDs; direct file reads now emit a valid encoded `[S1]` source card. | Pass |
| No response remains pending beyond its deadline | ChatStore timeout, stalled provider, non-cooperative provider-status, and non-cooperative retrieval tests all terminate. | Pass |
| Concurrent requests are asynchronous; one stall cannot serialize other chats | The mixed fast/slow/live/local/restricted/stalled/cancelled barrage observes overlapping generation and completes fast work independently. | Pass |
| Long streamed responses do not cause sustained transcript layout churn | A 1,000-token burst retains the complete answer while coalescing 1,002 previous transcript publications to at most eight; the Thread Sanitizer chat pass is clean. | Pass |
| Background connector/index work remains parallel and incremental | Connector tests cover all-kind parallel fan-out, one connector not blocking another, durable changed-chunk jobs, retained unchanged cache entries, and five-minute due/skip behavior. | Pass |
| Full deterministic suite passes | `swift test`: 245 tests, 4 opt-in live skips, 0 failures in 9.232 s. | Pass |
| Live Ollama completes without hangs or source contamination | 4 live tests passed; 16/16 soak prompts completed with 0 hangs, timeouts, failures, or leakage. See `live_ollama_report.md`. | Pass |
| Built app launches and remains responsive without foreground theft | `./script/build_and_run.sh --verify` succeeded; PID 75424 remained sleeping at 0.0% CPU and 0.4% memory. Launch registration reported `foreground=0`, `uiElement=1`. | Pass |

## Concurrency verification

`swift test --sanitize=thread --filter 'ChatStoreTests|ProductionPromptBarrageTests|StreamingChatResponderTests'` executed 53 tests with zero failures and no reported data races.

## Runtime notes

- Ollama `0.32.15` responded successfully at `127.0.0.1:11434` after relaunch.
- The launch log contains normal macOS AppIntents/Safari helper noise but no MacBrain crash, deadlock, or chat-routing failure.
- The deterministic corpus proves routing and lifecycle invariants, not that a finite local model can answer every possible question with frontier-model quality.
