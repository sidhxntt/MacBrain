# Open-Ended Local and System Queries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let natural questions reach authorized connectors when relevant, answer structured connector operations deterministically, preserve lexical evidence during semantic failures, and answer broad read-only questions about the current Mac from fresh typed facts.

**Architecture:** A pure query planner separates privacy, system, capability, structured, and evidence-search operations. SQLite executes structured connector plans; every non-casual content prompt receives a cheap lexical probe, while semantic/graph retrieval is optional enrichment. A typed system service samples current facts and bypasses response caching.

**Tech Stack:** Swift 6, Swift Testing, SQLite FTS5, existing Ollama provider, Foundation/AppKit/Darwin/IOKit system APIs.

---

### Task 1: Replace complete-question phrase routing with composable query plans

**Files:**
- Create: `Sources/MacBrain/Models/LocalQueryPlan.swift`
- Create: `Sources/MacBrain/Services/SourceVocabulary.swift`
- Create: `Sources/MacBrain/Services/LocalQueryPlanner.swift`
- Modify: `Sources/MacBrain/Services/SourceQueryScope.swift`
- Create: `Tests/MacBrainTests/LocalQueryPlannerTests.swift`

- [ ] **Step 1: Write failing parameterized planner tests**

Cover paraphrases, omitted “my,” multiple sources, public questions, follow-ups, and all eleven connector kinds.

```swift
import Testing
@testable import MacBrain

struct LocalQueryPlannerTests {
    @Test(arguments: [
        "How many notes do I have?",
        "What is the total number of Apple Notes?",
        "Give me my note count"
    ])
    func plansNotesCount(_ prompt: String) {
        let plan = LocalQueryPlanner().plan(prompt: prompt, records: [], conversation: [])
        #expect(plan == .connector(.count, scope: [.appleNotes]))
    }

    @Test(arguments: [
        "Who sent the message about ORBIT?",
        "What did the conversation decide?",
        "Summarize the launch handoff"
    ])
    func naturalContentQuestionsProbeEvidence(_ prompt: String) {
        let plan = LocalQueryPlanner().plan(prompt: prompt, records: [], conversation: [])
        #expect(plan == .evidenceSearch(scope: nil))
    }

    @Test func explicitSourcesOnlyNarrowScope() {
        let plan = LocalQueryPlanner().plan(
            prompt: "Compare ORBIT in Notes and Mail",
            records: [],
            conversation: []
        )
        #expect(plan == .evidenceSearch(scope: [.appleNotes, .appleMail]))
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter LocalQueryPlannerTests`

Expected: plan, vocabulary, and planner types are missing.

- [ ] **Step 3: Add plan types and composable normalization**

```swift
enum ConnectorQueryOperation: Equatable, Sendable {
    case count
    case newest(limit: Int)
    case oldest(limit: Int)
    case nextEvent
    case firstDueReminder
}

enum SystemQueryDomain: String, CaseIterable, Hashable, Sendable {
    case identity, specifications, memory, processor, storage, operatingSystem
    case power, applications, network, uptime, displays
}

struct SystemQueryPlan: Equatable, Sendable {
    enum ResponseStyle: Equatable, Sendable { case direct, synthesizedOverview }
    let domains: Set<SystemQueryDomain>
    let responseStyle: ResponseStyle
}

enum LocalQueryPlan: Equatable, Sendable {
    case restricted(response: String)
    case system(SystemQueryPlan)
    case connectorCapability(scope: Set<SourceConnectorKind>)
    case connector(ConnectorQueryOperation, scope: Set<SourceConnectorKind>?)
    case evidenceSearch(scope: Set<SourceConnectorKind>?)
    case casual
}
```

`SourceVocabulary` tokenizes punctuation/case once and resolves connector names, user-visible record names, and compact noun aliases. `LocalQueryPlanner` recognizes operation intent independently from source scope. Any nonrestricted, nonsystem, noncasual prompt not handled structurally becomes `.evidenceSearch`, including normal public questions; evidence acceptance later decides whether local material is used.

- [ ] **Step 4: Keep compatibility routing as a derived adapter**

Update `ChatQueryIntentRouter` and `SourceQueryScope` to delegate normalization/scope to the new planner/vocabulary so existing consumers and tests do not maintain a second phrase system.

- [ ] **Step 5: Run and verify GREEN**

Run: `swift test --filter 'LocalQueryPlannerTests|ChatQueryIntentRouterTests|SourceQueryScopeTests'`

Expected: planner and compatibility routing tests pass.

### Task 2: Add authorized structured document queries to SQLite

**Files:**
- Create: `Sources/MacBrain/Models/ConnectorQueryResult.swift`
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Create: `Tests/MacBrainTests/ConnectorStructuredQueryTests.swift`

- [ ] **Step 1: Write failing count/order/date tests**

Seed Notes, Calendar, and Reminders under searchable and permission-needed sources. Assert source-scoped count, newest/oldest ordering, the next future Calendar event from metadata `start`, and the earliest incomplete Reminder from `due`. Ineligible source IDs must never contribute.

```swift
@Test func countUsesOnlyEligibleScopedSourceIDs() async throws {
    let fixture = try await StructuredQueryFixture.make()
    #expect(try await fixture.database.documentCount(sourceIDs: [fixture.notesID]) == 3)
    #expect(try await fixture.database.documentCount(sourceIDs: []) == 0)
}

@Test func nextEventUsesStartMetadataRatherThanModificationDate() async throws {
    let fixture = try await StructuredQueryFixture.make()
    let result = try await fixture.database.documents(
        sourceIDs: [fixture.calendarID],
        metadataDateKey: "start",
        after: fixture.now,
        ascending: true,
        limit: 1
    )
    #expect(result.first?.title == "Next controlled event")
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ConnectorStructuredQueryTests`

Expected: structured query APIs are missing.

- [ ] **Step 3: Implement bounded typed database queries**

Add actor methods for `documentCount(sourceIDs:)`, date/order queries, and metadata predicates. Always require the caller-supplied eligible source-ID set, return immediately for an empty set, use bound parameters, exclude deleted rows, and apply `LIMIT` after source/metadata filtering.

Define:

```swift
struct ConnectorQueryResult: Equatable, Sendable {
    let operation: ConnectorQueryOperation
    let totalCount: Int?
    let documents: [ConnectorDocument]
    let capturedAt: Date
}
```

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: all count/order/date and authorization cases pass.

### Task 3: Execute and render structured connector plans

**Files:**
- Create: `Sources/MacBrain/Services/ConnectorQueryService.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Create: `Tests/MacBrainTests/ConnectorQueryServiceTests.swift`

- [ ] **Step 1: Write direct-answer tests**

Test “How many notes do I have?”, multi-source counts, no connected source, verified empty source, newest record, next Calendar event, and first due Reminder. Assert the service reads authoritative index health and includes source labels without model calls.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ConnectorQueryServiceTests`

Expected: service does not exist.

- [ ] **Step 3: Implement the service**

```swift
struct ConnectorQueryService: Sendable {
    let repository: LocalSourceRepository

    func response(
        for operation: ConnectorQueryOperation,
        scope: Set<SourceConnectorKind>?
    ) async -> String
}
```

The repository resolves scope to verified, authorized source IDs and performs the database query. Render counts and record lists deterministically. Never ask Ollama to calculate a count or invent a missing date. Distinguish not connected, permission needed, syncing/unverified, verified empty, and no matching record.

- [ ] **Step 4: Run and verify GREEN**

Run: `swift test --filter 'ConnectorQueryServiceTests|ConnectorStructuredQueryTests'`

Expected: all structured responses pass with zero provider calls.

### Task 4: Make lexical evidence the reliable first retrieval stage

**Files:**
- Modify: `Sources/MacBrain/Services/HybridEvidenceRetriever.swift`
- Modify: `Sources/MacBrain/Services/StreamingChatResponder.swift`
- Modify: `Sources/MacBrain/Services/EvidenceAcceptancePolicy.swift`
- Create: `Tests/MacBrainTests/LexicalFirstRetrievalTests.swift`

- [ ] **Step 1: Reproduce general-route bypass and semantic-timeout loss**

Seed a strong exact local fact. Ask it without `my`, `connected`, or a source kind and assert evidence reaches the model. Then use an embedding provider that never returns; assert the same lexical evidence still grounds the response before the enrichment deadline.

```swift
@Test func naturalPromptWithoutLocalPrefixUsesStrongLexicalEvidence() async throws {
    let fixture = try await LexicalFirstFixture.make(marker: "ORBIT-731")
    let response = try await fixture.responder.respond(to: "Who owns ORBIT-731?")
    #expect(response.contains("[S1]"))
    #expect(fixture.provider.lastSystemPrompt.contains("ORBIT-731"))
}

@Test func semanticTimeoutCannotEraseLexicalEvidence() async throws {
    let fixture = try await LexicalFirstFixture.make(
        marker: "CEDAR-204",
        embeddingBehavior: .neverReturns,
        retrievalTimeout: .milliseconds(20)
    )
    let response = try await fixture.responder.respond(to: "What is CEDAR-204?")
    #expect(response.contains("[S1]"))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter LexicalFirstRetrievalTests`

Expected: general prompt skips retrieval and hybrid timeout returns empty.

- [ ] **Step 3: Split retrieval into mandatory lexical and optional enrichment**

For `.evidenceSearch`, run `searchLexicalEvidence` first. Evaluate it with a policy that considers exact rare-token overlap, phrase overlap, source scope, and score. When accepted, pass lexical results into hybrid fusion and race only semantic/graph enrichment against the remaining budget. On timeout/error/cancellation of enrichment, return lexical results unchanged.

Explicit source scope with no evidence returns a scoped no-match message. Unscoped weak/no evidence proceeds to ordinary chat. Casual, restricted, capability, structured, and system plans perform no evidence search.

- [ ] **Step 4: Run and verify GREEN**

Run: `swift test --filter 'LexicalFirstRetrievalTests|HybridEvidenceRetrieverTests|StreamingChatResponderTests|ProductionPromptBarrageTests'`

Expected: strong natural matches ground, weak public prompts do not inject local evidence, and timeout preserves lexical results.

### Task 5: Integrate the query planner into the responder

**Files:**
- Modify: `Sources/MacBrain/Services/StreamingChatResponder.swift`
- Modify: `Sources/MacBrain/App/AppCoordinator.swift`
- Create: `Tests/MacBrainTests/QueryPlanResponderTests.swift`

- [ ] **Step 1: Write one terminal-path test per plan**

Cover restricted, system, connector capability, count, next event, explicit evidence, unscoped accepted evidence, unscoped rejected evidence, casual, and grounded follow-up. Assert which repository/provider methods were invoked and that every stream terminates once.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter QueryPlanResponderTests`

Expected: responder still switches on phrase-derived `ChatQueryIntent`.

- [ ] **Step 3: Execute a single plan once**

Inject `LocalQueryPlanner` and `ConnectorQueryService` into `StreamingChatResponder`. Resolve the plan at the top of the request, log only plan type/reason, then execute its terminal or evidence path. Keep `LocalFileReadTool` as an explicit file operation within evidence/structured planning. Reuse the existing citation-validation and provider-streaming boundary.

- [ ] **Step 4: Run and verify GREEN**

Run: `swift test --filter 'QueryPlanResponderTests|StreamingChatResponderTests|ConnectorAdversarialE2ETests'`

Expected: all plan paths terminate and existing provenance/isolation behavior remains green.

### Task 6: Expand typed, fresh read-only system facts

**Files:**
- Modify: `Sources/MacBrain/Models/LiveMacSnapshot.swift`
- Modify: `Sources/MacBrain/Models/SystemProfile.swift`
- Modify: `Sources/MacBrain/Services/LocalSystemProfileProvider.swift`
- Modify: `Sources/MacBrain/Services/LiveMacContextProvider.swift`
- Create: `Sources/MacBrain/Services/SystemQueryService.swift`
- Modify: `Sources/MacBrain/Services/LiveMacQueryRouter.swift`
- Create: `Tests/MacBrainTests/SystemQueryServiceTests.swift`

- [ ] **Step 1: Write supported-domain and unsupported-maximum tests**

Use a fixed system-facts provider to cover installed/current RAM, swap, total/available storage, processor and CPU counts, model/architecture, macOS, uptime/boot time, battery, applications, network interfaces, displays, multi-domain specifications, and an unsupported hardware maximum.

```swift
@Test func maximumSpecificationNeverInventsAProductLimit() async {
    let response = await service.response(to: "What is the maximum RAM this Mac supports?")
    #expect(response.contains("Installed memory: 24 GB"))
    #expect(response.contains("macOS does not report a supported maximum"))
}

@Test func dynamicStorageSamplesEveryRequest() async {
    _ = await service.response(to: "How much storage is available?")
    _ = await service.response(to: "What storage is free now?")
    #expect(await provider.sampleCount == 2)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SystemQueryServiceTests`

Expected: typed domains/service are missing.

- [ ] **Step 3: Extend typed facts and collection**

Add capabilities for identity/specification, operating system, swap, volumes, battery health when exposed, and displays. Collect with Foundation, Darwin `sysctl`, AppKit, and IOKit. Return optional values when macOS does not expose a fact. Do not expose serial numbers, credentials, SSIDs, IP addresses, private files, or process arguments.

- [ ] **Step 4: Implement deterministic and synthesis responses**

`SystemQueryService` detects requested domains from normalized tokens. Single/direct facts render without Ollama; broad specification questions return a bounded typed context for synthesis. Values are sampled per request and include capture time. Unsupported maximum/capacity questions state the limitation explicitly.

- [ ] **Step 5: Run and verify GREEN**

Run: `swift test --filter 'SystemQueryServiceTests|LiveMacQueryRouterTests|LiveMacContextTests|SystemProfileTests'`

Expected: all supported domains and limitation cases pass.

### Task 7: Tie cache behavior to authoritative revisions and dynamic plans

**Files:**
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Modify: `Sources/MacBrain/Services/ResponseCachingResponder.swift`
- Modify: `Tests/MacBrainTests/ResponseCachingResponderTests.swift`

- [ ] **Step 1: Write failing revision/access/dynamic tests**

Assert source commit, migration repair, pause, permission loss, resume, and deletion alter the SQLite-derived revision. Assert every `.system` plan and volatile structured plan bypasses cache even when wording lacks `now` or `current`.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ResponseCachingResponderTests`

Expected: revision comes from JSON and dynamic detection relies on word lists.

- [ ] **Step 3: Derive cacheability from the plan**

Have the cache wrapper call the same pure planner. Bypass system, restricted, file-content, and volatile structured plans. Derive `currentSourceRevision()` from sorted SQLite index revisions plus access status, not document JSON material.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: revision and dynamic-cache tests pass.

### Task 8: Verify open-ended connector and system behavior

**Files:**
- Modify: `Tests/StressTests/production_chat_acceptance_audit.md`
- Modify: `question-to-ask.md`

- [ ] **Step 1: Run focused query tests**

```sh
swift test --filter 'LocalQueryPlannerTests|ConnectorStructuredQueryTests|ConnectorQueryServiceTests|LexicalFirstRetrievalTests|QueryPlanResponderTests|SystemQueryServiceTests|ResponseCachingResponderTests'
```

Expected: zero failures.

- [ ] **Step 2: Run connector adversarial and full deterministic suites**

Run:

```sh
swift test --filter 'ConnectorAdversarialE2ETests|SourceAccessRetrievalTests|ProductionPromptBarrageTests'
swift test
```

Expected: zero deterministic failures and no authorization/cross-source leakage.

- [ ] **Step 3: Keep the manual artifact questions-only**

Update `question-to-ask.md` only after behavior exists. It must contain plain manual prompts—no automation instructions, fixtures, expected results, status labels, or setup prose. Include count, natural content, follow-up/evidence, cross-source, live RAM/storage/specification, authorization, and freshness questions.

- [ ] **Step 4: Record exact evidence**

Document which named tests prove natural retrieval activation, authoritative counts, lexical timeout fallback, fresh system sampling, cache invalidation, citations, and access isolation. Do not label live macOS/Ollama behavior passed until runtime verification runs.
