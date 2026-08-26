# Local Mail Store Connector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace AppleScript-based Apple Mail indexing with a fast, resumable connector backed by local Mail metadata and `.emlx` files.

**Architecture:** Discover a readable Mail `Envelope Index`, inspect its schema, and adapt a metadata query to that schema. Resolve only locally cached `.emlx` bodies from the indexed paths using bounded concurrency, then merge each completed batch before advancing a stable cursor. Keep the existing source state and indexed documents intact until a local-store batch succeeds.

**Tech Stack:** Swift 6, Foundation, SQLite CLI, Swift concurrency, XCTest, macOS Full Disk Access.

---

### Task 1: Make Mail-store discovery testable

**Files:**
- Modify: `Sources/MacBrain/Services/AppleLibraryConnectors.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] **Step 1: Write a failing test for versioned Envelope Index discovery.**

```swift
func testAppleMailStoreLocatorUsesNewestExistingEnvelopeIndex() throws {
    let root = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(at: root.appending(path: "V10/MailData"), withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "V10/MailData/Envelope Index"))
    XCTAssertEqual(AppleMailStoreLocator.firstExistingDatabase(in: root)?.lastPathComponent, "Envelope Index")
}
```

- [ ] **Step 2: Run the test and verify it fails because the locator cannot accept an injected root.**

Run: `swift test --filter SourceConnectorTests/testAppleMailStoreLocatorUsesNewestExistingEnvelopeIndex`

- [ ] **Step 3: Add `firstExistingDatabase(in:)` and keep the production wrapper rooted at `~/Library/Mail`.**

```swift
static func firstExistingDatabase(in root: URL) -> URL? {
    ["V11", "V10", "V9", "V8", "V7"].lazy
        .map { root.appending(path: "\($0)/MailData/Envelope Index") }
        .first { FileManager.default.fileExists(atPath: $0.path) }
}
```

- [ ] **Step 4: Re-run the focused test and confirm it passes.**

### Task 2: Add a schema-adaptive metadata reader

**Files:**
- Create: `Sources/MacBrain/Services/AppleMailLocalStore.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] **Step 1: Write failing tests for parsing a metadata row and rejecting an unsupported schema.**

```swift
XCTAssertEqual(try parser.rows("42\u{1F}Subject\u{1F}sender@example.com\u{1F}Inbox\u{1F}/path/42.emlx").count, 1)
XCTAssertThrowsError(try AppleMailSchema(tables: []))
```

- [ ] **Step 2: Run the focused tests and verify failure.**

Run: `swift test --filter SourceConnectorTests/testAppleMailLocalStore`

- [ ] **Step 3: Implement `AppleMailSchema`, `AppleMailMetadataRow`, and a metadata query that selects only identifiers, subject, sender, mailbox, date, and local file path.**

```swift
struct AppleMailMetadataRow: Sendable {
    let rowID: Int
    let subject: String
    let sender: String
    let mailbox: String
    let emlxPath: String
}
```

- [ ] **Step 4: Re-run focused tests and confirm parsing never reads body data.**

### Task 3: Resolve local bodies with bounded concurrency

**Files:**
- Modify: `Sources/MacBrain/Services/AppleMailLocalStore.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] **Step 1: Write failing tests for `.emlx` header stripping, absent body fallback, and a concurrency cap of four readers.**

```swift
XCTAssertEqual(AppleMailBodyParser.parse("123\nSubject body").text, "Subject body")
XCTAssertEqual(AppleMailBodyParser.parse("missing").text, "")
```

- [ ] **Step 2: Implement `AppleMailBodyReader` using a throwing task group with `maxConcurrentReads = 4`; each task returns a document or metadata-only fallback.**

- [ ] **Step 3: Verify cancellation stops scheduling additional body reads and focused tests pass.**

### Task 4: Replace the Apple Mail connector

**Files:**
- Modify: `Sources/MacBrain/Services/SourceConnectors.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceCoordinator.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] **Step 1: Write failing connector tests for a stable row-ID cursor, 100 metadata rows per batch, partial-body success, and source progress.**

```swift
XCTAssertEqual(batch.nextOffset, 101)
XCTAssertEqual(batch.documents.count, 100)
XCTAssertEqual(batch.progressDescription, "Indexed 100 mail history · 100 total")
```

- [ ] **Step 2: Implement `AppleMailLocalStoreConnector` as `BatchedSourceConnector`, using the row-ID cursor and document merge already used by Messages.**

- [ ] **Step 3: Retain the existing AppleScript connector only as an explicit fallback when no readable local store exists; do not silently reset previously indexed documents.**

- [ ] **Step 4: Verify the Mail source starts from its saved cursor and reaches `ready` after the final page.**

### Task 5: Expose probe result and verify on this Mac

**Files:**
- Modify: `Sources/MacBrain/Stores/SourceLibraryStore.swift`
- Modify: `Sources/MacBrain/Views/SourceManagerView.swift`
- Test: `Tests/MacBrainTests/SourceConnectorTests.swift`

- [ ] **Step 1: Add test coverage that the source menu’s read-only probe reports database discovery/schema readability without querying message rows.**
- [ ] **Step 2: Report the connector mode, indexed batch count, and any actionable Full Disk Access/local-cache failure in the source row.**
- [ ] **Step 3: Run `swift test`, then `bash script/build_and_run.sh --verify`.**
- [ ] **Step 4: From the launched app, run the read-only probe, start a Mail sync, and verify the first persisted local-store batch increases the existing count without UI blocking.**
