# Browser Profiles Connector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Safari with an explicit user-selected Browser Profiles connector for Chrome, Brave, Firefox, and Arc.

**Architecture:** Add a browser-profile source kind and typed browser configuration. A focused connector parses Chromium JSON/SQLite data and Firefox Places SQLite data into normalized documents; a narrow Automation adapter adds optional open-tab snapshots without blocking stored-profile sync.

**Tech Stack:** Swift 6, SwiftUI, Foundation, AppKit file picker, `sqlite3`, `osascript`, XCTest.

---

### Task 1: Source model and consent UI

**Files:**
- Modify: `Sources/MacBrain/Models/SourceConnector.swift`
- Modify: `Sources/MacBrain/Views/SourceManagerView.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [x] Write failing tests for legacy Safari migration and selectable browser kinds.
- [x] Add `BrowserKind`, `browserProfile` connector kind, configuration fields, and Safari-to-browser migration.
- [x] Add browser selection and profile-folder picker to Sources; require profile selection before Connect and sync.
- [x] Run source connector model tests.

### Task 2: Profile parsing and normalized documents

**Files:**
- Create: `Sources/MacBrain/Services/BrowserProfileConnector.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceCoordinator.swift`
- Test: `Tests/MacBrainTests/BrowserProfileConnectorTests.swift`

- [x] Write failing Chromium and Firefox fixtures covering bookmarks, history, reading list, and downloads.
- [x] Implement Chromium bookmark JSON and history/download SQLite parsing.
- [x] Implement Firefox Places SQLite parsing.
- [x] Add profile/browser/data-type provenance metadata and bounded history extraction.
- [x] Run browser connector tests.

### Task 3: Optional current-tab snapshots and documentation

**Files:**
- Create: `Sources/MacBrain/Services/BrowserTabSnapshotProvider.swift`
- Modify: `Sources/MacBrain/Services/BrowserProfileConnector.swift`
- Modify: `docs/MVP/05-indexing.md`
- Test: `Tests/MacBrainTests/BrowserProfileConnectorTests.swift`

- [x] Write failing test proving tab snapshots append without blocking profile documents.
- [x] Implement Chromium-browser Automation scripts and non-fatal unavailable-tab behavior.
- [x] Update connector documentation to replace Safari with Browser Profiles.
- [ ] Run full test suite and package with `bash script/build_and_run.sh --bundle` without launching MacBrain.
