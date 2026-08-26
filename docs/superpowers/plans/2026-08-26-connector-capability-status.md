# Connector Capability Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer direct Apple Notes and other connector capability questions from current connector state instead of attempting content retrieval.

**Architecture:** A pure `LocalSourceCapabilityResponder` recognizes direct ability/access questions, resolves explicitly named source kinds through `SourceQueryScope`, and renders state from `ConnectorRecord` values. `StreamingChatResponder` invokes it before file reading, provider-status work, embeddings, retrieval, and model generation; content-bearing prompts retain the existing path.

**Tech Stack:** Swift 6, Swift Testing, Swift Concurrency, existing `LocalSourceRepository` actor and `StreamingChatResponder` stream.

---

### Task 1: Reproduce the capability-question failure

**Files:**
- Create: `Tests/MacBrainTests/LocalSourceCapabilityResponderTests.swift`

- [x] **Step 1: Write the failing end-to-end responder tests**

Create a Swift Testing suite with an in-memory temporary repository and a complete `InferenceProvider` probe. Cover a disconnected Apple Notes request plus parameterized ready, syncing, authorization-needed, paused, and failed records. Every status case must assert the human-facing status text, no `### Sources`, and zero status/model/embedding calls. Add a content-bearing counterexample that seeds an Apple Notes document and proves “Can you read my Apple Notes and summarize AURORA?” invokes the provider, retrieves evidence, and renders `[S1]`.

- [x] **Step 2: Run the test to verify RED**

Run:

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache \
  swift test --filter LocalSourceCapabilityResponderTests
```

Expected: the disconnected case fails because the current responder returns `I couldn't find matching material in your connected local sources.` and calls provider status.

### Task 2: Implement deterministic connector capability responses

**Files:**
- Create: `Sources/MacBrain/Services/LocalSourceCapabilityResponder.swift`
- Modify: `Sources/MacBrain/Services/StreamingChatResponder.swift`

- [x] **Step 1: Add the pure capability responder**

Implement this interface:

```swift
enum LocalSourceCapabilityResponder {
    static func response(for prompt: String, records: [ConnectorRecord]) -> String?
}
```

It must return `nil` unless the prompt is a direct ability/access question and `SourceQueryScope.resolve(prompt:)` yields at least one kind. Render one concise status paragraph per named connector. A paused or failed source may still have searchable retained material, so describe only its synchronization state. Reject prompts containing a content operation or target (`search`, `find`, `summarize`, `show`, `tell`, `about`, `what`, `who`, `when`, `where`, `why`, `how`) so they retain retrieval behavior.

- [x] **Step 2: Place the response at the correct boundary**

In `StreamingChatResponder.stream`, after restricted and live-Mac handling but before `LocalFileReadTool`, `selectedModel`, and retrieval, call:

```swift
if let response = LocalSourceCapabilityResponder.response(
    for: prompt,
    records: await repository.allRecords()
) {
    continuation.yield(response)
    continuation.finish()
    Self.logTerminal("connector-capability", startedAt: requestStartedAt)
    return
}
```

- [x] **Step 3: Run the focused test to verify GREEN**

Run the Task 1 command. Expected: all status and content-boundary cases pass.

### Task 3: Verify integration and document the fixed behavior

**Files:**
- Modify: `Tests/StressTests/production_chat_acceptance_audit.md`

- [x] **Step 1: Run routing and streaming regressions**

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache \
  swift test --filter 'LocalSourceCapabilityResponderTests|ChatQueryIntentRouterTests|StreamingChatResponderTests'
```

Expected: zero failures.

- [x] **Step 2: Run the full deterministic suite**

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache swift test
```

Expected: zero failures; opt-in live Ollama checks skip unless enabled.

- [x] **Step 3: Record the regression**

Add a short acceptance-audit entry describing the capability-status boundary and the test suite that prevents regression. Do not commit: the user requested work in the current checkout and it already contains unrelated uncommitted changes that must remain untouched.
