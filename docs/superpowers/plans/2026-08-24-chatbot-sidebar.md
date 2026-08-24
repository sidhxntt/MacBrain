# Chatbot Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a polished local chatbot inside the always-on-top Notch Brain sidebar with a functional mock conversation.

**Architecture:** Keep SwiftUI responsible for presentation. Add a `@MainActor` `ChatStore` backed by a small `ChatResponder` protocol and deterministic local responder. Split conversation, message bubble, and composer into focused views.

**Tech Stack:** Swift 6, SwiftUI, AppKit panel hosting, XCTest, Swift Package Manager.

---

### Task 1: Add chat domain and local responder

**Files:**
- Create: `Sources/MacBrain/Models/ChatMessage.swift`
- Create: `Sources/MacBrain/Services/ChatResponder.swift`
- Create: `Sources/MacBrain/Services/LocalMockChatResponder.swift`
- Create: `Sources/MacBrain/Stores/ChatStore.swift`
- Test: `Tests/MacBrainTests/ChatStoreTests.swift`

- [ ] Write tests for whitespace rejection, user-first ordering, deterministic mock response, duplicate-send prevention, and clear.
- [ ] Run `swift test --disable-sandbox --filter ChatStoreTests`; expect failure until types exist.
- [ ] Implement `ChatMessage`, `ChatResponder`, `LocalMockChatResponder`, and `ChatStore` with `@MainActor`, async response handling, and local-only behavior.
- [ ] Run focused tests; expect all chat tests to pass.

### Task 2: Build conversation and composer views

**Files:**
- Create: `Sources/MacBrain/Views/ChatConversationView.swift`
- Create: `Sources/MacBrain/Views/ChatMessageBubble.swift`
- Create: `Sources/MacBrain/Views/ChatComposer.swift`

- [ ] Add welcome state, scrollable messages, role-specific bubbles, loading indicator, VoiceOver labels, and Reduce Motion-aware scrolling.
- [ ] Add compact composer, attachment placeholder, local-mode label, send button, clear action, and Return/Enter submission.
- [ ] Use adaptive material and standard SwiftUI controls; avoid new dependencies or Cloud/network code.

### Task 3: Integrate chat into sidebar

**Files:**
- Modify: `Sources/MacBrain/Views/SidebarView.swift`
- Modify: `Sources/MacBrain/Services/SidebarPanelController.swift` only if lifecycle ownership needs explicit cleanup.

- [ ] Replace `ContentUnavailableView` with the chat conversation and composer.
- [ ] Create one `ChatStore` for the sidebar view lifetime and preserve existing header, right-edge geometry, rounded left corners, borderless right edge, and slide transitions.
- [ ] Ensure panel recreation does not create competing stores or tasks.

### Task 4: Verify and package

**Files:**
- Modify: `Tests/MacBrainTests/*` only if integration assertions are needed.

- [ ] Run `swift test --disable-sandbox` with project-specific cache paths; expect all existing and chat tests to pass.
- [ ] Run `bash ./script/build_and_run.sh --bundle`; expect a fresh `dist/MacBrain.app`.
- [ ] Inspect changed files and verify no Cloud, network, UIKit, or third-party dependency was introduced.
