# Safe Source Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Mail body/header fields, Reminder priority, and Photos collection membership without indexing attachments or media content.

**Architecture:** Extend the existing connector documents only. Mail continues reading the local Envelope Index and never reads attachment tables or files; Reminders adds the native priority field; Photos resolves user collections containing each asset and stores their names as text metadata. Fixture tests verify each field and preserve existing outputs.

**Tech Stack:** Swift, EventKit, Photos, XCTest, SQLite-backed local source index.

---

### Task 1: Mail document enrichment

**Files:**
- Modify: `Sources/MacBrain/Services/AppleLibraryConnectors.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] Write a fixture test with local Mail row fields for sender, recipient, body, and sent timestamp; assert the resulting `ConnectorDocument` contains every field and has no attachment field.
- [ ] Run `swift test --filter SourceConnectorTests/testAppleMailLocalStorePreservesHeadersAndBodyWithoutAttachments` and confirm it fails before the parser/query change.
- [ ] Extend the selected local Mail columns and document formatter; do not join attachment tables or read attachment files.
- [ ] Re-run the focused test and confirm it passes.

### Task 2: Reminder priority

**Files:**
- Modify: `Sources/MacBrain/Services/AppleProductivityConnectors.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] Add a pure formatter test for a reminder priority label and metadata value.
- [ ] Run its focused XCTest and confirm the expected priority field is initially absent.
- [ ] Add priority text and metadata to the existing `RemindersConnector` document only.
- [ ] Re-run the focused XCTest and confirm it passes.

### Task 3: Photo collection membership

**Files:**
- Modify: `Sources/MacBrain/Services/AppleProductivityConnectors.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] Add a pure collection-name formatter test for joined album names.
- [ ] Run its focused XCTest and confirm it fails before implementation.
- [ ] Resolve the asset’s `PHAssetCollection` names and store only names in the text/metadata; do not request image/video data, pixel buffers, or visual analysis.
- [ ] Re-run the focused XCTest and confirm it passes.

### Task 4: Regression verification

**Files:**
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] Run `swift test --filter 'SourceConnectorTests|BrowserProfileConnectorTests'`.
- [ ] Run `MACBRAIN_LIVE_OLLAMA=1 swift test --disable-sandbox --jobs 1` and confirm zero failures.
