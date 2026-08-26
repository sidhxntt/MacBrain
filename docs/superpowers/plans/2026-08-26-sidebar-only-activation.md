# Sidebar-Only Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent MacBrain from taking focus during app launch and background work, while preserving focus when the user explicitly opens or clicks its sidebar.

**Architecture:** App activation remains a responsibility of the sidebar panel controller and click handler, which are invoked by explicit user gestures. The SwiftUI app delegate and startup coordinator become non-activating so source synchronization cannot foreground the app.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, Swift Package Manager.

---

### Task 1: Remove automatic application activation

**Files:**

- Modify: `Sources/MacBrain/App/MacBrainApp.swift:24-29`
- Modify: `Sources/MacBrain/App/AppCoordinator.swift:67-77`
- Test: `Tests/MacBrainTests/ActivationPolicyTests.swift`

- [ ] **Step 1: Write the failing test**

Add a source-level regression test that asserts neither normal launch method contains an application-activation call:

```swift
func testStartupDoesNotForceMacBrainToForeground() throws {
    let appSource = try String(contentsOf: sourceURL("Sources/MacBrain/App/MacBrainApp.swift"))
    let coordinatorSource = try String(contentsOf: sourceURL("Sources/MacBrain/App/AppCoordinator.swift"))

    XCTAssertFalse(appSource.contains("applicationDidFinishLaunching(_ notification: Notification) {\n        NSApp.setActivationPolicy(OverlayWindowPolicy.applicationActivationPolicy)\n        NSApp.activate"))
    XCTAssertFalse(coordinatorSource.contains("await Task.yield()\n            NSApp.activate"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ActivationPolicyTests/testStartupDoesNotForceMacBrainToForeground`

Expected: FAIL because launch and startup currently call `NSApp.activate(ignoringOtherApps: true)`.

- [ ] **Step 3: Write the minimal implementation**

Delete the foregrounding call from each startup method, retaining the activation policy setup and all initialization work:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(OverlayWindowPolicy.applicationActivationPolicy)
    coordinator.start()
}
```

```swift
Task { @MainActor [sourceLibrary] in
    await Task.yield()
    await sourceLibrary.reload()
    // existing initialization continues unchanged
}
```

- [ ] **Step 4: Run focused tests**

Run: `swift test --filter ActivationPolicyTests && swift test --filter ActivationBarInteractionTests`

Expected: PASS. Startup is non-activating; explicit activation-bar interaction behavior remains covered.

- [ ] **Step 5: Launch and verify**

Run: `./script/build_and_run.sh --verify`

Expected: the app starts successfully without an unconditional foreground activation; sidebar interaction remains the only route that brings its panel forward.
