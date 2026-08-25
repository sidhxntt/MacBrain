# Phase 4 Ollama Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give MacBrain a local-only Ollama provider with guided setup, streaming chat, embedding support, cancellation, diagnostics, and deterministic tests.

**Architecture:** Keep the provider independent of SwiftUI. `OllamaClient` owns HTTP and NDJSON decoding, `OllamaProvider` owns availability/model/setup state, and `StreamingChatResponder` bridges the provider into `ChatStore`. UI observes a main-actor store and never formats HTTP payloads. When Ollama is absent, existing local-search responses remain available.

**Tech Stack:** Swift 6, SwiftUI, Foundation `URLSession`, `AsyncThrowingStream`, Ollama localhost API, XCTest.

---

### Task 1: Provider contracts and HTTP client

**Files:**
- Create: `Sources/MacBrain/Models/InferenceProvider.swift`
- Create: `Sources/MacBrain/Services/OllamaClient.swift`
- Create: `Tests/MacBrainTests/OllamaClientTests.swift`

- [ ] Write failing tests for model discovery, health failure, streamed NDJSON output, malformed events, HTTP errors, timeout, and cancellation.
- [ ] Implement typed provider status, model metadata, model download progress, embedding result, and actionable provider errors.
- [ ] Implement local-only `URLSession` requests to `/api/version`, `/api/tags`, `/api/pull`, `/api/chat`, and `/api/embed` with NDJSON streaming.
- [ ] Verify targeted tests pass.

### Task 2: Setup, model choice, and diagnostics

**Files:**
- Create: `Sources/MacBrain/Stores/InferenceStore.swift`
- Create: `Sources/MacBrain/Services/OllamaProvider.swift`
- Create: `Tests/MacBrainTests/InferenceStoreTests.swift`

- [ ] Write failing tests for missing runtime, offline server, missing model, model-ready state, local model pull state, retry, and cancellation.
- [ ] Implement a provider-neutral protocol and default local model profiles: a 7B–14B chat model and lightweight embedding model.
- [ ] Implement non-blocking refresh, pull/download, cancellation, retry, and health persistence in SQLite settings.
- [ ] Verify targeted tests pass.

### Task 3: Stream responses into chat

**Files:**
- Modify: `Sources/MacBrain/Services/ChatResponder.swift`
- Create: `Sources/MacBrain/Services/StreamingChatResponder.swift`
- Modify: `Sources/MacBrain/Stores/ChatStore.swift`
- Modify: `Sources/MacBrain/Views/ChatConversationView.swift`
- Modify: `Sources/MacBrain/Views/ChatComposer.swift`
- Create: `Tests/MacBrainTests/StreamingChatResponderTests.swift`

- [ ] Write failing tests proving partial assistant output appears in order, cancellation preserves a useful partial response, and failure leaves an actionable local error.
- [ ] Extend chat responder interfaces with streaming while retaining the current local-search fallback.
- [ ] Wire structured task cancellation through `ChatStore`; show a compact cancel control while output streams.
- [ ] Verify targeted tests pass.

### Task 4: Native setup and settings UI

**Files:**
- Create: `Sources/MacBrain/Views/OllamaSetupView.swift`
- Create: `Sources/MacBrain/Views/OllamaSettingsView.swift`
- Modify: `Sources/MacBrain/Views/MacBrainPreferencesView.swift`
- Modify: `Sources/MacBrain/App/AppCoordinator.swift`
- Modify: `Sources/MacBrain/Views/MacBrainWorkspaceView.swift`
- Create: `Tests/MacBrainTests/OllamaSetupViewTests.swift`

- [ ] Write failing construction/state tests for setup and settings surfaces.
- [ ] Add a native settings section with local-processing explanation, runtime status, disk/RAM estimates, selected models, download/test/retry actions, and non-blocking diagnostics.
- [ ] Use the existing adaptive glass roles and standard SwiftUI controls; do not change global sidebar behavior.
- [ ] Verify targeted tests pass.

### Task 5: Documentation and full verification

**Files:**
- Modify: `docs/MVP/04-ollama.md`
- Modify: `docs/README.md`

- [ ] Document setup behavior, default models, fallback mode, local-only guarantee, and manual Ollama acceptance test.
- [ ] Run `swift test --disable-sandbox`, `bash script/build_and_run.sh --bundle`, and `git diff --check`.
- [ ] Commit verified Phase 4 work, push `codex/phase-4`, and open a draft PR.
