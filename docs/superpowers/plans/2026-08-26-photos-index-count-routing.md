# Photos Index Count Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route “How many photos do I have indexed?” to the authoritative verified Photos count rather than unscoped local retrieval.

**Architecture:** Keep count execution in `ConnectorQueryService` and `LocalSourceRepository`. Add only a narrow first-person count scope fallback in `SourceVocabulary`, then exercise it through the production `StreamingChatResponder` with a controlled SQLite-backed Photos fixture.

**Tech Stack:** Swift 6, Swift Testing, SQLite-backed `LocalSourceRepository`.

---

### Task 1: Reproduce the phrase-routing defect

**Files:**
- Modify: `Tests/MacBrainTests/LocalQueryPlannerTests.swift`

- [ ] **Step 1: Write the failing planner test**

```swift
@Test("First-person Photos index count is a structured Photos query")
func plansPhotosIndexCount() {
    let plan = LocalQueryPlanner().plan(
        prompt: "How many photos do I have indexed?",
        records: [],
        conversation: []
    )

    #expect(plan == .connector(.count, scope: [.photos]))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter LocalQueryPlannerTests`

Expected: the new test fails because the current plan is `.evidenceSearch(scope: nil)`.

- [ ] **Step 3: Add the minimal count-scope fallback**

```swift
var scope = SourceVocabulary(records: records).scope(in: prompt)
if scope == nil {
    scope = SourceVocabulary.firstPersonCountScope(in: normalized)
}
```

Implement `firstPersonCountScope(in:)` to require a count phrase, `i`/`my`/`we`/`our`, and an existing connector count noun such as `photos`.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter LocalQueryPlannerTests`

Expected: all planner cases pass, including the screenshot prompt.

### Task 2: Prove the response is correct rather than merely nonempty

**Files:**
- Modify: `Tests/MacBrainTests/QueryPlanResponderTests.swift`

- [ ] **Step 1: Write failing end-to-end tests**

Create a verified Photos fixture with two documents and assert the screenshot prompt returns `2 photos`, has no source card, and makes zero provider calls. Add a refresh-state case that writes an uncommitted third Photos document and assert the same prompt still returns `2 photos`, never `3 photos`.

- [ ] **Step 2: Verify RED**

Run: `swift test --filter QueryPlanResponderTests`

Expected: the screenshot-prompt test follows evidence retrieval instead of the connector query path.

- [ ] **Step 3: Reuse the existing structured query path**

No count rendering or repository changes are needed once the planner emits `.connector(.count, scope: [.photos])`.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter 'LocalQueryPlannerTests|QueryPlanResponderTests|ConnectorQueryServiceTests'`

Expected: exact verified count, refresh snapshot, and zero-provider assertions pass.

### Task 3: Verify the full app logic

**Files:**
- Modify: `Tests/StressTests/test_report.md`

- [ ] **Step 1: Run the deterministic suite**

Run: `swift test --quiet`

Expected: zero failures; record the actual XCTest/Swift Testing results and command in the report.

- [ ] **Step 2: Build the app**

Run: `./script/build_and_run.sh --verify`

Expected: build, signing verification, and app launch complete successfully.
