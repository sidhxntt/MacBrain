# Live Mac Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer live Mac-state questions from fresh native data without indexing that data or waiting on RAG or an unbounded model request.

**Architecture:** A typed `LiveMacSnapshot` is sampled only when a query is routed to a live capability. `LiveMacQueryRouter` selects supported capabilities and formats deterministic Markdown responses. Other questions retain local RAG plus Ollama; live-context questions bypass source retrieval and receive a bounded model stream only if no deterministic response applies.

**Tech Stack:** Swift 6, Foundation, Darwin/Mach, AppKit, SwiftPM, XCTest, Ollama localhost.

---

### Task 1: Typed live snapshot

**Files:**
- Create: `Sources/MacBrain/Models/LiveMacSnapshot.swift`
- Create: `Sources/MacBrain/Services/LiveMacContextProvider.swift`
- Test: `Tests/MacBrainTests/LiveMacContextTests.swift`

- [ ] **Step 1: Write failing tests** for a snapshot containing memory, storage, uptime, CPU load, active app names, and network interface names.
- [ ] **Step 2: Run** `swift test --filter LiveMacContextTests` and confirm symbols are missing.
- [ ] **Step 3: Implement** native bounded reads using Mach VM counters, `getloadavg`, filesystem attributes, boot time, `NSWorkspace`, and `getifaddrs`.
- [ ] **Step 4: Re-run** focused tests and confirm live counters are non-negative and no capability persists source data.

### Task 2: Live-query routing

**Files:**
- Create: `Sources/MacBrain/Services/LiveMacQueryRouter.swift`
- Modify: `Sources/MacBrain/Services/StreamingChatResponder.swift`
- Test: `Tests/MacBrainTests/LiveMacQueryRouterTests.swift`
- Test: `Tests/MacBrainTests/StreamingChatResponderTests.swift`

- [ ] **Step 1: Write failing tests** for memory, CPU, storage, network, active-app, uptime, and combined overview queries.
- [ ] **Step 2: Run** focused tests and confirm router is absent.
- [ ] **Step 3: Implement** intent classification and direct Markdown responses. Route before model status and before repository search.
- [ ] **Step 4: Re-run** tests and confirm direct responses never invoke inference or RAG.

### Task 3: Bounded inference fallback

**Files:**
- Modify: `Sources/MacBrain/Services/OllamaClient.swift`
- Test: `Tests/MacBrainTests/OllamaClientTests.swift`

- [ ] **Step 1: Write a failing test** for no-first-token timeout.
- [ ] **Step 2: Run** `swift test --filter OllamaClientTests` and confirm timeout is missing.
- [ ] **Step 3: Implement** a 15-second first-visible-token deadline that cancels the local request and produces a recoverable error.
- [ ] **Step 4: Re-run** focused tests and confirm normal token streaming remains unchanged.

### Task 4: Verification and delivery

**Files:**
- Verify: `Tests/MacBrainTests/*`
- Build: `script/build_and_run.sh --bundle`

- [ ] **Step 1: Run** full `swift test --disable-sandbox`.
- [ ] **Step 2: Run** opt-in local Ollama tests.
- [ ] **Step 3: Build** `dist/MacBrain.app` without launch.
- [ ] **Step 4: Commit and push** the verified Phase 4 changes.
