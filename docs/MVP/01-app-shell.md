# Phase 01 — Native macOS App Shell

## Goal

Create the launchable Swift macOS application and edge-attached sidebar before adding AI functionality.

## Deliverables

- SwiftUI app entry point.
- AppKit `NSPanel` controller.
- Right/left edge placement on the active display.
- Compact and expanded sidebar states.
- Show, hide, dismiss, focus, resize, and display-change behavior.
- Basic logging and panel tests.

## Implementation sequence

- [ ] Inspect the repository and preserve its existing Xcode/SwiftPM structure.
- [ ] Create `NotchBrainApp.swift` and a dependency-injected application coordinator.
- [ ] Create `SidebarPanelController` using an `NSPanel` configured for floating, non-activating behavior where appropriate.
- [ ] Position the panel against the active screen’s visible frame and recalculate on display changes.
- [ ] Add minimum/maximum width constraints and compact/expanded presentation state.
- [ ] Create a placeholder `SidebarView` with a title, empty state, and close/expand controls.
- [ ] Add `os.Logger` events for launch, panel show/hide, resize, focus, display changes, and failures.
- [ ] Write unit tests using panel/display abstractions; manually verify one and multiple monitors.

## Exit criteria

The app launches from Xcode, opens a native edge sidebar, stays above normal applications, resizes within bounds, dismisses cleanly, and repositions correctly after display changes.
