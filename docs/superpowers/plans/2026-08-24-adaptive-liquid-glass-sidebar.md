# Adaptive Liquid Glass Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the complete sidebar with native Liquid Glass on macOS 26+ and a visually matched system-material fallback on macOS 14–25.

**Architecture:** Add one semantic adaptive-glass modifier with availability-gated native and fallback rendering. Existing sidebar, composer, and message views keep one shared hierarchy and apply roles for shell, composer, messages, and prominent actions.

**Tech Stack:** Swift 6, SwiftUI, macOS 14 minimum deployment, macOS 26 Liquid Glass APIs, XCTest, Swift Package Manager.

---

### Task 1: Add semantic adaptive glass roles

**Files:**
- Create: `Sources/MacBrain/Views/AdaptiveGlassRole.swift`
- Test: `Tests/MacBrainTests/AdaptiveGlassRoleTests.swift`

- [ ] Add failing tests asserting shell, composer, assistant-message, user-message, and prominent-action roles expose stable fallback material strength, tint intent, outline opacity, and shadow configuration.
- [ ] Run `swift test --disable-sandbox --filter AdaptiveGlassRoleTests`; expect compilation failure because `AdaptiveGlassRole` does not exist.
- [ ] Implement the role enum and testable fallback configuration values without importing AppKit or networking APIs.
- [ ] Run focused tests; expect all adaptive-role tests to pass.

### Task 2: Add availability-gated rendering modifier

**Files:**
- Create: `Sources/MacBrain/Views/AdaptiveGlassModifier.swift`

- [ ] Implement a generic `View.adaptiveGlass(role:in:)` modifier.
- [ ] Inside `if #available(macOS 26.0, *)`, map roles to native `glassEffect` styles and use `.interactive()` only for composer and prominent-action roles.
- [ ] In the fallback path, use system materials, semantic tint overlays, low-contrast outlines, and role-specific shadows.
- [ ] Keep one view hierarchy; do not duplicate sidebar or chat layouts.
- [ ] Run `swift build --disable-sandbox`; expect successful macOS 14 deployment compilation with the current SDK.

### Task 3: Convert complete sidebar hierarchy

**Files:**
- Modify: `Sources/MacBrain/Views/SidebarView.swift`
- Modify: `Sources/MacBrain/Views/ChatComposer.swift`
- Modify: `Sources/MacBrain/Views/ChatConversationView.swift`
- Modify: `Sources/MacBrain/Views/ChatMessageBubble.swift`

- [ ] Replace shell purple/black overlays with `.adaptiveGlass(role: .shell, in: sidebarShape)`.
- [ ] Apply `.composer` glass to the compact composer and `.prominentAction` glass to the send button while preserving Return submission and exact two-row layout.
- [ ] Apply assistant/user message roles to message bubbles and replace manual white-opacity text with semantic foreground styles.
- [ ] Keep header actions, right-edge border removal, rounded leading corners, slide transitions, selectable text, auto-scroll, loading state, and chat behavior unchanged.
- [ ] Add full accessibility labels to icon-only header and composer controls.

### Task 4: Verify both compatibility paths

**Files:**
- Test: `Tests/MacBrainTests/AdaptiveGlassRoleTests.swift`
- Verify: `Package.swift`
- Verify: `script/build_and_run.sh`

- [ ] Confirm `Package.swift` still declares `.macOS(.v14)`.
- [ ] Run full tests using project-local cache paths; expect zero failures.
- [ ] Run `bash ./script/build_and_run.sh --bundle`; expect a fresh `dist/MacBrain.app`.
- [ ] Launch the `.app` bundle and verify the current runtime path renders transparent adaptive surfaces with readable controls and unchanged panel behavior.
- [ ] Search sources for removed hard-coded shell overlays, duplicated sidebar hierarchies, Cloud/network calls, and third-party UI dependencies; expect none.
