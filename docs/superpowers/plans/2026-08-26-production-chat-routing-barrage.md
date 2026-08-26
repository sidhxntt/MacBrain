# Production Chat Routing and Prompt Barrage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MacBrain route general, live-macOS, explicit-local, and implicit-local questions safely, then verify the behavior with a broad deterministic prompt barrage and a bounded live-Ollama soak.

**Architecture:** A pure `ChatQueryIntentRouter` chooses the response path without touching storage. Explicit local requests use hybrid retrieval; implicit local requests must pass a lexical `EvidenceAcceptancePolicy` before semantic evidence is allowed. Grounded source identifiers are stored on assistant messages so short follow-ups can inherit local intent, while general/casual prompts never query local storage.

**Tech Stack:** Swift 6, Swift Concurrency, SwiftUI, XCTest, SQLite FTS5, Ollama HTTP streaming, `os.Logger`.

---

### Task 1: Deterministic Query Intent Router

**Files:**
- Create: `Sources/MacBrain/Services/ChatQueryIntentRouter.swift`
- Create: `Tests/MacBrainTests/ChatQueryIntentRouterTests.swift`

- [ ] **Step 1: Write failing table-driven router tests**

Define canonical cases for `.casual`, `.general`, `.liveMac`, `.explicitLocal`, `.implicitLocal`, and `.restricted`. Include greetings, public knowledge, writing/coding/math, macOS state, connected sources, file paths/extensions, project ownership/deadlines, unauthorized-source requests, Unicode, punctuation, and short grounded follow-ups. Add deterministic case/punctuation/polite-prefix variants and assert at least 250 inputs are exercised.

- [ ] **Step 2: Run the router tests and verify RED**

Run: `swift test --filter ChatQueryIntentRouterTests`

Expected: compilation failure because `ChatQueryIntentRouter` and `ChatQueryIntent` do not exist.

- [ ] **Step 3: Implement the pure router**

Create:

```swift
enum ChatQueryIntent: String, Sendable, Equatable {
    case casual, general, liveMac, explicitLocal, implicitLocal, restricted
}

struct ChatQueryRoute: Sendable, Equatable {
    let intent: ChatQueryIntent
    let reason: String
}

struct ChatQueryIntentRouter: Sendable {
    func route(prompt: String, conversation: [ChatMessage]) -> ChatQueryRoute
}
```

Normalize apostrophes, case, whitespace, and terminal punctuation. Keep casual matching bounded to whole conversational phrases. Detect privacy restrictions first, live Mac capabilities second, explicit personal/source/path cues third, grounded short follow-ups fourth, internal project/ownership/deadline cues fifth, and default to general.

- [ ] **Step 4: Run the router tests and verify GREEN**

Run: `swift test --filter ChatQueryIntentRouterTests`

Expected: all router cases pass, with the corpus-size assertion proving at least 250 variants ran.

### Task 2: Absolute Evidence Relevance Gate

**Files:**
- Create: `Sources/MacBrain/Services/EvidenceAcceptancePolicy.swift`
- Create: `Tests/MacBrainTests/EvidenceAcceptancePolicyTests.swift`
- Modify: `Sources/MacBrain/Services/HybridEvidenceRetriever.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Modify: `Tests/MacBrainTests/HybridEvidenceRetrieverTests.swift`

- [ ] **Step 1: Write failing evidence-policy tests**

Cover strong exact phrase matches, named entities, ownership/deadline phrases, stop-word-only overlap, semantically ranked but lexically unrelated chunks, short ambiguous prompts, and explicit-local prompts with sparse evidence. Require a structured result:

```swift
struct EvidenceAcceptance: Sendable, Equatable {
    let accepted: Bool
    let reason: String
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter EvidenceAcceptancePolicyTests`

Expected: compilation failure because the policy does not exist.

- [ ] **Step 3: Implement lexical candidate retrieval and acceptance**

Expose a lexical-only search path that uses SQLite FTS5 and never invokes embeddings. Implement normalized significant-token extraction with a stop-word set, phrase/entity coverage, and absolute thresholds. Explicit-local intent may accept any non-empty authorized result; implicit-local intent requires lexical evidence with sufficient significant-token coverage. Semantic rank alone must never satisfy implicit acceptance.

- [ ] **Step 4: Verify evidence and existing hybrid behavior**

Run: `swift test --filter 'EvidenceAcceptancePolicyTests|HybridEvidenceRetrieverTests|MacBrainDatabaseTests'`

Expected: all selected tests pass and unrelated semantic candidates are rejected.

### Task 3: Persist Grounding Metadata for Follow-ups

**Files:**
- Modify: `Sources/MacBrain/Models/ChatMessage.swift`
- Modify: `Sources/MacBrain/Models/StoredRecords.swift`
- Modify: `Sources/MacBrain/Services/LocalChatSessionRepository.swift`
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Modify: `Sources/MacBrain/Stores/ChatStore.swift`
- Modify: `Tests/MacBrainTests/ChatStoreTests.swift`
- Modify: `Tests/MacBrainTests/MacBrainDatabaseTests.swift`

- [ ] **Step 1: Write failing persistence and follow-up-context tests**

Assert that a completed assistant response containing rendered citation cards records its citation IDs, survives session persistence/reload, and supplies grounded context to the next responder call. Assert that a new chat and a general ungrounded response contain no inherited source IDs.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'ChatStoreTests|MacBrainDatabaseTests'`

Expected: failures because `ChatMessage` has no grounding metadata.

- [ ] **Step 3: Add backward-compatible grounding storage**

Add `groundingSourceIDs: [String]` to `ChatMessage` with a default empty value. Add a nullable/defaulted JSON column through schema migration 10 and map it in `StoredMessage`. At response completion, parse only known rendered citation cards and attach their IDs to the assistant message before final persistence. Preserve metadata when replacing streamed message text.

- [ ] **Step 4: Verify persistence and chat lifecycle**

Run: `swift test --filter 'ChatStoreTests|MacBrainDatabaseTests|ResponseCachingResponderTests'`

Expected: all selected tests pass, including backward decoding and new-chat reset.

### Task 4: Integrate Routing, Retrieval Gating, and Safe Terminal Responses

**Files:**
- Modify: `Sources/MacBrain/Services/StreamingChatResponder.swift`
- Modify: `Sources/MacBrain/Services/CitationValidator.swift`
- Modify: `Tests/MacBrainTests/StreamingChatResponderTests.swift`
- Modify: `Tests/MacBrainTests/OllamaClientTests.swift`

- [ ] **Step 1: Write failing responder routing tests**

Seed local documents that deliberately collide with general prompts such as Kubernetes, Netflix, Python, weather, and “what's up.” Assert casual/general/live/restricted routes perform zero embedding and lexical calls. Assert explicit local routes retrieve. Assert implicit routes retrieve only after lexical acceptance. Cover short grounded follow-ups, topic switches, weak evidence, invented citations, timeout, cancellation, malformed streams, and one terminal completion.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'StreamingChatResponderTests|OllamaClientTests'`

Expected: routing and weak-evidence assertions fail against the current always-retrieve behavior.

- [ ] **Step 3: Integrate router and gate**

Route before retrieval. Send `.casual` and `.general` directly to Ollama, `.liveMac` to live providers, `.restricted` to policy, `.explicitLocal` to hybrid retrieval, and `.implicitLocal` through lexical acceptance before hybrid retrieval. If evidence is rejected, regenerate the general instruction without source context. Bound fallback excerpts to three entries and 600 characters each, strip source-card markup from fallback prose, and never yield raw evidence on cancellation.

Add privacy-safe `Logger` events containing route, decision reason, evidence count, acceptance reason, stage duration, and terminal category—never prompt or excerpt text.

- [ ] **Step 4: Verify responder integration**

Run: `swift test --filter 'StreamingChatResponderTests|OllamaClientTests|ChatStoreTests'`

Expected: all selected tests pass with no local leakage on general routes and every stream terminating.

### Task 5: Deterministic Production Prompt Barrage

**Files:**
- Create: `Tests/MacBrainTests/ProductionPromptBarrageTests.swift`
- Create: `Tests/StressTests/production_prompt_corpus.md`

- [ ] **Step 1: Write the barrage corpus and failing integration test**

Build at least 300 seeded cases across casual, general knowledge, writing, translation, summarization, math, coding, live macOS, explicit local, implicit local, follow-ups, ambiguity, Unicode/multilingual text, misspellings, prompt injection, privacy, provider failures, cancellation, and concurrency. Each case specifies expected intent, whether source access is allowed, terminal state, and forbidden leakage markers.

- [ ] **Step 2: Run and verify RED for uncovered cases**

Run: `swift test --filter ProductionPromptBarrageTests`

Expected: at least one assertion fails until all routing categories and variants are implemented.

- [ ] **Step 3: Implement only the minimal corpus-driven corrections**

Adjust router normalization and acceptance thresholds without adding prompt-specific exact patches. Keep category rules explainable and rerun after each correction.

- [ ] **Step 4: Add bounded concurrency barrage**

Run mixed general, local, live, stalled, and cancelled streams in a task group. Assert fast requests finish without waiting for the stalled request, all tasks reach a terminal result by their deadlines, and the provider observes concurrent starts.

- [ ] **Step 5: Verify deterministic barrage**

Run: `swift test --filter ProductionPromptBarrageTests`

Expected: 300+ seeded cases and concurrency checks pass with zero pending requests or leakage.

### Task 6: Live Ollama Soak and Final Verification

**Files:**
- Modify: `Tests/MacBrainTests/OllamaLiveIntegrationTests.swift`
- Create: `Tests/StressTests/live_ollama_report.md`
- Modify: `Tests/StressTests/README.md`

- [ ] **Step 1: Add an opt-in live barrage**

Add 12–20 representative prompts using the configured chat and embedding models. Use bounded concurrency of two, a per-prompt first-token/total deadline, and checks for non-empty output, maximum output size, valid terminal state, no general-route source markup, and no raw HTML/code evidence fallback. Capture category, route, duration, outcome, and failure class without recording private prompt/source content.

- [ ] **Step 2: Run deterministic full verification**

Run: `swift test`

Expected: all deterministic tests pass; live-only tests skip without their environment flag.

- [ ] **Step 3: Run the live Ollama soak**

Run: `MACBRAIN_LIVE_OLLAMA=1 swift test --filter OllamaLiveIntegrationTests`

Expected: all live prompts terminate successfully within configured deadlines. Classify model-quality misses separately from routing/runtime failures.

- [ ] **Step 4: Record evidence and relaunch**

Write aggregate counts and timings to `Tests/StressTests/live_ollama_report.md`, run `./script/build_and_run.sh --verify`, and confirm the launched app is responsive at idle and during one general plus one local query.

- [ ] **Step 5: Completion audit**

Re-read `docs/superpowers/specs/2026-08-26-production-chat-routing-design.md` and map every acceptance criterion to a passing test, live result, or runtime observation. Do not mark complete while any criterion lacks direct evidence.
