# Production chat acceptance audit

Date: 2026-08-26

## Requirement evidence

| Requirement | Authoritative current evidence | Result |
|---|---|---|
| Fresh install starts without connected sources | `FreshInstallConnectorE2ETests.connectSyncAskAndRestartRequiresNoSourceEdit` begins from an empty temporary SQLite repository. | Pass (deterministic) |
| First-run onboarding explains local processing and explicit connector consent | `OnboardingPresentationTests`, `OnboardingStoreTests`, and `MacBrainWorkspaceViewTests` cover page copy, persisted completion, limited completion, shared app state, first presentation, and reopening from Settings. | Pass (deterministic) |
| Connecting starts an immediate sync without editing source data | `FreshInstallConnectorE2ETests.connectSyncAskAndRestartRequiresNoSourceEdit` verifies a pre-existing note, zero connector mutations, immediate sync, searchable health, answer, count, and restart. | Pass (deterministic) |
| Normal connection drains optional enrichment without blocking lexical readiness | `SourceLibraryStoreInitialSyncTests.addAndSyncDrainsQueuedEnrichmentAfterTheVerifiedCommit` verifies completed embedding and graph jobs after the committed lexical generation. | Pass (deterministic) |
| Ready means authorization, scan, atomic index commit, and verification succeeded | `ConnectorLifecycleTests.connectBecomesReadyOnlyAfterSearchableCommit`, `SourceIndexCommitTests`, and `ConnectorIndexHealthTests`. | Pass (deterministic) |
| An authorized empty source is healthy and explicitly empty | `ConnectorLifecycleTests.zeroDocumentInitialSyncCreatesVerifiedEmptyReadyState` and `FreshInstallConnectorE2ETests.verifiedEmptySourceIsReadyWithoutAnEdit`. | Pass (deterministic) |
| SQLite is the only post-migration runtime authority | `LocalSourceBootstrapTests.completedMigrationHydratesFromSQLiteWhenLegacySnapshotIsMissing` and `completedMigrationDoesNotResurrectADeletedSourceFromStaleLegacyJSON`. | Pass (deterministic) |
| Restart preserves connected, verified, queryable state | `FreshInstallConnectorE2ETests.connectSyncAskAndRestartRequiresNoSourceEdit` reopens the same database and asks again; bootstrap tests separately cover missing/stale legacy JSON. | Pass (deterministic) |
| Interrupted startup never promotes an unverified source | `ConnectorLifecycleTests.interruptedUnverifiedInitialSyncRestartsInsteadOfBecomingOptimisticallyReady` and `interruptedRefreshUsesVerifiedIndexWithoutRequiringSourceChanges`. | Pass (deterministic) |
| Interrupted batched refresh never skips pages after relaunch | `ConnectorLifecycleTests.interruptedBatchedRefreshRestartsFromTheFirstPage` verifies that a persisted offset is discarded, page zero is replayed, and only the complete generation becomes searchable. | Pass (deterministic) |
| Sources refresh every 300 seconds while the app is open | `ConnectorRefreshSchedulerTests.loopWaitsExactlyFiveMinutesAndStopsCleanly` uses a controllable clock and observes no work at 299 seconds and work at 300 seconds. | Pass (deterministic) |
| Refresh work is bounded, concurrent, cancellable, and failure-isolated | `ConnectorRefreshSchedulerTests.refreshesOnlyDueSourcesWithBoundedConcurrencyAndFailureIsolation`, `ConnectorLifecycleTests.cancellingInitialSyncCancelsScanningAndPreventsACommit`, and the focused Thread Sanitizer run. | Pass (deterministic + sanitizer) |
| Manual and automatic requests coalesce per source | `ConnectorLifecycleTests.concurrentSyncCallersReceiveTheSameCommittedGeneration` proves one adapter invocation and two identical committed results; `cancellingACoalescedWaiterDoesNotCancelTheSharedSync` covers waiter cancellation. | Pass (deterministic) |
| Previous verified content remains searchable during a refresh or sibling failure | `FreshInstallConnectorE2ETests.refreshWhileChattingAndFailureIsolation` and `ConnectorLifecycleTests.failedRefreshRetainsTheLastVerifiedSearchableGeneration`. | Pass (deterministic) |
| Natural connector questions do not require a fixed command prefix | `LocalQueryPlannerTests` sends every ordinary content question to the evidence probe; `LexicalFirstRetrievalTests.testNaturalPromptWithoutLocalPrefixUsesStrongLexicalEvidence` proves grounding through the production responder. | Pass (deterministic) |
| Explicit connector wording narrows every retrieval path | `SourceAccessRetrievalTests` covers scoped lexical, semantic, generic, direct-file, fallback, and responder behavior; the 198-case connector matrix covers cross-source isolation. | Pass (deterministic) |
| Capability questions report actual verified connector state | `LocalSourceCapabilityResponderTests` and `QueryPlanResponderTests.testCapabilityPlanReadsVerifiedHealthWithoutProvider` cover disconnected, syncing, ready, empty, paused, failed, and permission-needed states. | Pass (deterministic) |
| Counts, newest/oldest, next event, and first due reminder use SQLite operations | `ConnectorStructuredQueryTests`, `ConnectorQueryServiceTests`, and `QueryPlanResponderTests` verify authoritative counts and metadata dates without model calculation. | Pass (deterministic) |
| Lexical evidence survives semantic timeout and missing Ollama | `LexicalFirstRetrievalTests.testSemanticTimeoutPreservesAlreadyAcceptedLexicalEvidence` and `testUnavailableModelStillReturnsAcceptedLexicalEvidence`. | Pass (deterministic) |
| Public/general questions do not leak weakly matching local content | `LexicalFirstRetrievalTests.testPublicKnowledgePromptWithOnlyGenericOverlapRemainsGeneral`, `EvidenceAcceptancePolicyTests`, and `ProductionPromptBarrageTests`. | Pass (deterministic) |
| Citations contain known provenance and unsafe destinations are rejected | `ConnectorCitationMetadataTests`, `ChatCitationCardTests`, `CitationValidator` responder regressions, and all 198 adversarial connector cases. | Pass (deterministic) |
| Authorization loss and deletion exclude all old data and invalidate cache | `FreshInstallConnectorE2ETests.permissionAndRemovalIsolation`, `SourceAccessRetrievalTests`, and `ResponseCachingResponderTests.testAuthorizationRevocationInvalidatesAnAlreadyCachedGroundedResponse`. | Pass (deterministic) |
| Read-only Mac questions use fresh typed facts without model dependence | `FreshInstallSystemE2ETests.broadSystemQuestionsUseFreshTypedFactsWithoutInference` covers RAM, storage, specifications, macOS, uptime, battery, apps, network, displays, and unsupported maximum RAM wording; `SystemQueryServiceTests` proves resampling. | Pass (deterministic) |
| Restricted bulk personal/credential requests terminate without source reads | `QueryPlanResponderTests.testRestrictedPlanTerminatesWithoutProviderWork`, `StreamingChatResponderTests`, and `ProductionPromptBarrageTests`. | Pass (deterministic) |
| Response cache tracks committed content and access revisions | `ResponseCachingResponderTests` covers generation, status, authorization, deletion, citation metadata, dynamic system bypass, and structured-query bypass. | Pass (deterministic) |
| Full deterministic suite is green | `swift test --quiet`: 277 XCTest tests, 5 explicit live skips, 0 failures; 91 Swift Testing tests in 20 suites, 0 failures. | Pass |
| Focused concurrent paths are race-free under Thread Sanitizer | `swift test --sanitize=thread --filter 'ConnectorLifecycleTests|LocalSourceBootstrapTests|SourceIndexCommitTests'`: 22 Swift Testing cases, no race report. | Pass |
| Current release and packaged app launch | `swift build -c release` passed; `./script/build_and_run.sh --verify` rebuilt, re-signed, launched, and confirmed the process. | Pass (launch only) |
| Current local-model and verified-fallback answer quality | Current-tree `OllamaLiveIntegrationTests`: 5/5 tests, 66/66 connector/dimension outcomes, and 16/16 soak prompts passed. Telemetry recorded 47 model, 8 verified-evidence fallback, and 11 permission-state answer paths without conflating them. | Pass (live synthetic) |
| Existing connectors remain recognized without modifying their source | The packaged app relaunched the schema-13 production database with all 17 records ready and verified, zero duplicate name/kind groups, and exactly one Safari record; it settled at 0% CPU and approximately 165 MB RSS. No source item was created or modified for recognition. | Pass (runtime metadata) |
| The real five-minute production refresh preserves verified sources | The exact final bundle began its scheduled cycle at 21:46:56 after the five-minute wait and completed all 17 connected sources by 21:53:46. It ended with 17 ready records, 17 verified indexes, zero index errors, and zero duplicate groups. Status, health, counts, and timing were observed without inspecting document bodies. | Pass (runtime metadata) |
| Real Apple permission prompts and answers against existing personal data | This requires user interaction with the launched app, explicit permission changes, and the manual prompts in `question-to-ask.md`. Synthetic tests and metadata inspection cannot prove the final user-visible result. | Unverified (manual) |

## Current command summary

- Focused connector core and access isolation: 81 XCTest + 40 Swift Testing cases, zero failures.
- Focused query behavior: 30 XCTest + 17 Swift Testing cases, zero failures.
- Fresh-install/adversarial acceptance: 24 Swift Testing cases across 7 suites, including all 198 parameterized connector cases, zero failures.
- Complete suite: 277 XCTest + 91 Swift Testing cases, zero failures; 5 opt-in live tests skipped.
- Thread Sanitizer: 22 Swift Testing cases, zero failures or reported races.
- Live Ollama: 5 tests, 66 connector/dimension outcomes, and 16 production-soak prompts, zero failures.
- Release build and packaged process launch: passed.

## Manual boundary

`question-to-ask.md` contains only manual prompts. The remaining real-world pass must use connectors the user explicitly chooses. It must not require creating or modifying a note merely to make MacBrain recognize an already connected source. Interactive permission behavior and answers against personal content must be recorded as manual evidence, not inferred from synthetic tests.
