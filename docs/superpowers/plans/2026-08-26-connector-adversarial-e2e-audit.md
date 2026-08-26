# Connector Adversarial End-to-End Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove and harden fact accuracy, source type, citations, freshness, permissions, and cross-source isolation for every MacBrain connector through deterministic and live end-to-end tests.

**Architecture:** A pure source-scope resolver constrains explicitly named connector requests. The repository computes currently eligible source IDs and passes them through every lexical, semantic, and graph retrieval path. Retrieval evidence carries honest optional destinations, while citation cards expose connector type without fabricating file URLs. A generated controlled corpus drives the production responder for all eleven connector kinds and all six audit dimensions.

**Tech Stack:** Swift 6, Swift Testing, XCTest for the existing live suite, Swift Concurrency, SQLite FTS5, Ollama HTTP streaming.

---

### Task 1: Explicit Connector Scope Resolver

**Files:**
- Create: `Sources/MacBrain/Services/SourceQueryScope.swift`
- Create: `Tests/MacBrainTests/SourceQueryScopeTests.swift`

- [x] **Step 1: Write parameterized failing scope tests**

Use Swift Testing and define explicit cases for every connector plus public-knowledge counterexamples:

```swift
import Testing
@testable import MacBrain

struct SourceQueryScopeTests {
    @Test(arguments: [
        ("Search my Apple Notes for AURORA", Set([.appleNotes])),
        ("Find the AURORA email in my Mail", Set([.appleMail])),
        ("Which AURORA event is on my calendar?", Set([.calendar])),
        ("Which AURORA item is in my reminders?", Set([.reminders])),
        ("Find AURORA in my contacts", Set([.contacts])),
        ("Find AURORA in my browser history", Set([.browserProfile])),
        ("Who said AURORA in my Messages?", Set([.messages])),
        ("Find AURORA in my Photos metadata", Set([.photos])),
        ("Which AURORA title is in my Apple Books library?", Set([.books])),
        ("Find AURORA in my connected folder", Set([.folder])),
        ("Find AURORA in this Git repository", Set([.gitRepository]))
    ])
    func resolvesNamedConnector(prompt: String, expected: Set<SourceConnectorKind>) {
        #expect(SourceQueryScope.resolve(prompt: prompt) == expected)
    }

    @Test(arguments: [
        "How does Apple Mail work?",
        "What is a git repository?",
        "Explain browser history databases",
        "How do calendars calculate leap years?"
    ])
    func generalKnowledgeDoesNotBecomeASourceScope(prompt: String) {
        let route = ChatQueryIntentRouter().route(prompt: prompt, conversation: [])
        #expect(route.intent == .general)
    }
}
```

- [x] **Step 2: Run the test and verify RED**

Run: `swift test --filter SourceQueryScopeTests`

Expected: compilation fails because `SourceQueryScope` does not exist.

- [x] **Step 3: Implement the pure resolver**

Create a `SourceQueryScope` enum with `static func resolve(prompt:) -> Set<SourceConnectorKind>?`. Normalize case, apostrophes, punctuation, and whitespace. Match connector names and explicit personal-source phrases, allow multiple named connector kinds, and return `nil` when no connector is explicitly named. Keep routing independent: this resolver constrains retrieval but never activates it.

- [x] **Step 4: Run the focused router and scope tests**

Run: `swift test --filter 'SourceQueryScopeTests|ChatQueryIntentRouterTests'`

Expected: all scope and existing routing cases pass.

### Task 2: Authorization-Aware, Source-Scoped Retrieval

**Files:**
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Modify: `Sources/MacBrain/Services/HybridEvidenceRetriever.swift`
- Modify: `Sources/MacBrain/Services/MacBrainDatabase.swift`
- Modify: `Sources/MacBrain/Services/StreamingChatResponder.swift`
- Modify: `Tests/MacBrainTests/HybridEvidenceRetrieverTests.swift`
- Create: `Tests/MacBrainTests/SourceAccessRetrievalTests.swift`

- [x] **Step 1: Write failing authorization and isolation regressions**

Seed two colliding documents under different connector kinds. Verify that a `.needsAuthorization` source is absent from lexical and hybrid results and that a Mail scope cannot return Notes evidence. Also use a provider spy to assert an empty eligible-source set performs zero embedding calls.

```swift
@Test func revokedSourceCannotBeRetrievedFromCachedChunks() async throws {
    let fixture = try await RetrievalFixture.make(kinds: [.appleMail])
    try await fixture.seed(kind: .appleMail, marker: "MAIL-PRIVATE-731")
    try await fixture.setStatus(.needsAuthorization, kind: .appleMail)

    let result = await fixture.repository.searchLexicalEvidence(
        "MAIL-PRIVATE-731",
        sourceKinds: [.appleMail]
    )
    #expect(result.evidence.isEmpty)
}

@Test func namedMailQueryCannotReturnCollidingNotesEvidence() async throws {
    let fixture = try await RetrievalFixture.make(kinds: [.appleMail, .appleNotes])
    try await fixture.seed(kind: .appleMail, marker: "ORBIT mail fact")
    try await fixture.seed(kind: .appleNotes, marker: "ORBIT notes decoy")

    let result = await fixture.repository.searchLexicalEvidence(
        "Find ORBIT in my Mail",
        sourceKinds: [.appleMail]
    )
    #expect(Set(result.evidence.map(\.sourceType)) == [.appleMail.rawValue])
}
```

- [x] **Step 2: Run the regressions and verify RED**

Run: `swift test --filter SourceAccessRetrievalTests`

Expected: the revoked cached source remains searchable and scoped repository APIs are missing.

- [x] **Step 3: Add source filters to every database retrieval path**

Extend these APIs with `sourceIDs: Set<UUID>? = nil`:

```swift
func searchChunks(matching: String, limit: Int, matchAllTerms: Bool, sourceIDs: Set<UUID>? = nil) throws -> [StoredChunk]
func searchDocuments(matching: String, limit: Int, sourceIDs: Set<UUID>? = nil) throws -> [StoredDocument]
func nearestChunks(to: [Float], limit: Int, sourceIDs: Set<UUID>? = nil) throws -> [StoredChunk]
func graphRelatedChunks(to: [UUID], limit: Int, sourceIDs: Set<UUID>? = nil) throws -> [StoredChunk]
```

Apply the filter inside SQL/vector candidate selection, before `LIMIT`, so a high-ranked ineligible chunk cannot crowd out eligible evidence. Treat `nil` as unscoped and an empty set as no results.

- [x] **Step 4: Propagate eligibility through repository and hybrid retrieval**

Add repository entry points accepting `sourceKinds: Set<SourceConnectorKind>? = nil`. Compute eligible IDs from current records whose status is not `.needsAuthorization`, intersect with the requested kinds, and return `.empty` before embedding when the intersection is empty. Apply the same predicate to the in-memory fallback.

- [x] **Step 5: Resolve scope once in the responder**

For `.explicitLocal` and `.implicitLocal`, call `SourceQueryScope.resolve(prompt:)` and pass the result to lexical and hybrid retrieval. Keep `.casual`, `.general`, `.liveMac`, and `.restricted` at zero source access.

- [x] **Step 6: Verify retrieval behavior**

Run: `swift test --filter 'SourceAccessRetrievalTests|HybridEvidenceRetrieverTests|StreamingChatResponderTests|MacBrainDatabaseTests'`

Expected: authorization and isolation regressions pass with all prior retrieval tests green.

### Task 3: Honest Connector-Aware Citation Cards

**Files:**
- Modify: `Sources/MacBrain/Models/RetrievalEvidence.swift`
- Modify: `Sources/MacBrain/Services/HybridEvidenceRetriever.swift`
- Modify: `Sources/MacBrain/Services/LocalSourceRepository.swift`
- Modify: `Sources/MacBrain/Services/CitationValidator.swift`
- Modify: `Sources/MacBrain/Support/ChatCitationCard.swift`
- Modify: `Sources/MacBrain/Views/AssistantMessageContent.swift`
- Modify: `Tests/MacBrainTests/ChatCitationCardTests.swift`
- Modify: `Tests/MacBrainTests/HybridEvidenceRetrieverTests.swift`

- [x] **Step 1: Write failing linked and unlinked citation tests**

Assert that browser evidence renders its real HTTPS URL and source type, a folder renders its file URL, and an opaque Notes identifier produces an unlinked Notes card rather than `file:///opaque-id`.

```swift
@Test func opaqueConnectorIDIsNotRenderedAsAFakeFileURL() throws {
    let evidence = RetrievalEvidence.fixture(
        sourceType: .appleNotes,
        sourcePath: "x-coredata://opaque-note-id",
        sourceURL: nil
    )
    let rendered = CitationValidator.renderedSources(for: [evidence])
    let card = try #require(ChatCitationCard.parse(from: rendered).first)
    #expect(card.sourceType == SourceConnectorKind.appleNotes.rawValue)
    #expect(card.url == nil)
    #expect(rendered.contains("file://") == false)
}
```

- [x] **Step 2: Run citation tests and verify RED**

Run: `swift test --filter 'ChatCitationCardTests|HybridEvidenceRetrieverTests'`

Expected: parser cannot represent source type or an unlinked card, and opaque IDs become file URLs.

- [x] **Step 3: Carry an optional real destination on evidence**

Add `sourceURL: URL?` to `RetrievalEvidence` with a backward-compatible default. Derive it only from trusted metadata:

- absolute file paths for Folder, Git file, and Books records;
- valid `http` or `https` metadata URLs for Browser Profiles;
- a valid explicit connector URL when one exists;
- otherwise `nil`.

Never convert an opaque external identifier into a file URL.

- [x] **Step 4: Render and parse typed cards**

Use these stable forms:

```text
- [S1](https://example.test/item) [browserProfile] Controlled title
- [S2] [appleNotes] Controlled note
```

Update `ChatCitationCard` to store `sourceType: String` and `url: URL?`. Parse both forms. Update `AssistantMessageContent` to show the type and render “Open source” only when `url` is non-nil.

- [x] **Step 5: Verify citation regressions and responder output**

Run: `swift test --filter 'ChatCitationCardTests|HybridEvidenceRetrieverTests|StreamingChatResponderTests|ChatStoreTests'`

Expected: all known IDs remain valid, typed cards parse, and no opaque source is mislabeled as a file.

### Task 4: Complete Deterministic Six-Dimension Matrix

**Files:**
- Create: `Tests/MacBrainTests/ConnectorAdversarialE2ETests.swift`
- Create: `Tests/MacBrainTests/ConnectorAdversarialFixtures.swift`
- Create: `Tests/StressTests/connector_adversarial_matrix.md`

- [x] **Step 1: Define controlled fixtures matching all connector document shapes**

Create one `ConnectorAdversarialFixture` per `SourceConnectorKind`. Each fixture contains three exact facts, a real or intentionally absent destination, an updated marker, a stale marker, and three connector-specific prompts. Use unique tokens that cannot be answered from model priors.

Examples include `NOTES-QUARTZ-417`, `MAIL-EMBER-582`, `CALENDAR-ORBIT-639`, `REMINDER-CEDAR-204`, `CONTACT-VIOLET-731`, `BROWSER-ATLAS-845`, `MESSAGE-HARBOR-316`, `PHOTO-SAFFRON-902`, `BOOK-LANTERN-558`, `FOLDER-TUNDRA-664`, and `GIT-MERIDIAN-193`.

- [x] **Step 2: Add a completeness test before behavior tests**

```swift
@Test func matrixCoversEveryConnectorAndDimensionWithMultipleQuestions() {
    #expect(Set(fixtures.map(\.kind)) == Set(SourceConnectorKind.allCases))
    for kind in SourceConnectorKind.allCases {
        for dimension in AuditDimension.allCases {
            let cases = matrix.filter { $0.kind == kind && $0.dimension == dimension }
            #expect(cases.count >= 3, "\(kind.rawValue) lacks adversarial \(dimension.rawValue) coverage")
        }
    }
}
```

Generate at least `11 connectors × 6 dimensions × 3 questions = 198` stable cases.

- [x] **Step 3: Drive fact, type, and citation cases through `StreamingChatResponder`**

Use temporary SQLite repositories and a deterministic provider that reads the actual selected evidence in the system prompt, emits only evidence facts with their provided IDs, and records every request. For each case assert terminal completion, all expected facts, no forbidden fact, parsed citation IDs, expected source type, and expected destination behavior.

- [x] **Step 4: Drive freshness mutations through the production repository**

For every connector, test three independent phases: replace the same external ID with the new marker, reconcile/delete the document, and remove the source. Ask the same targeted prompt after each mutation and assert the stale marker and stale citation never reappear.

- [x] **Step 5: Drive permission and restricted cases through the responder**

For every connector, mark a previously indexed record `.needsAuthorization`, ask three connector-specific prompts, and assert no evidence enters the model prompt and no private marker appears. Also assert bulk-secret and unconnected-source requests terminate before retrieval.

- [x] **Step 6: Drive colliding cross-source cases**

For every connector, seed its expected fact and a second connector with the same query marker plus a decoy fact. Ask three explicitly named-source variants and assert only the requested source type and fact reach the provider and citation cards.

- [x] **Step 7: Run the complete deterministic matrix**

Run: `swift test --filter ConnectorAdversarialE2ETests`

Expected: 198+ generated cases pass, every request terminates, and zero stale, unauthorized, or cross-source marker leaks.

### Task 5: Live Ollama Connector Quality Barrage

**Files:**
- Modify: `Tests/MacBrainTests/OllamaLiveIntegrationTests.swift`
- Modify: `Tests/StressTests/live_ollama_report.md`

- [x] **Step 1: Add an opt-in controlled connector barrage**

Seed the same eleven controlled connector records. Run connector-specific fact/citation/source-type prompts plus mutation, authorization, and collision phases through `OllamaProvider`. Use bounded concurrency of two and a 45-second per-request deadline.

- [x] **Step 2: Assert model-quality outcomes**

For every grounded completion, require expected unique facts, forbid decoy/stale/private facts, require typed known citation cards, and reject the direct-evidence fallback. Record stable case IDs, routes, first-token latency, total latency, and failure category without recording personal content.

- [x] **Step 3: Run the live barrage**

Run:

```sh
env MACBRAIN_LIVE_OLLAMA=1 \
  CLANG_MODULE_CACHE_PATH=/tmp/notchbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/notchbrain-swiftpm-cache \
  swift test --filter OllamaLiveIntegrationTests
```

Expected: all connector quality cases pass with zero inaccurate fact, wrong source type, citation error, stale value, permission leak, isolation leak, timeout, or hang.

- [x] **Step 4: Correct only evidence-backed failures**

If a live case fails, classify the failing boundary from captured route, selected evidence, model output, and rendered cards. Add the smallest deterministic reproduction before modifying routing, retrieval, prompt instruction, or citation validation. Rerun the failed live case after the deterministic regression is green.

### Task 6: Full Verification and Acceptance Audit

**Files:**
- Modify: `Tests/StressTests/README.md`
- Modify: `Tests/StressTests/test_report.md`
- Modify: `Tests/StressTests/production_chat_acceptance_audit.md`

- [x] **Step 1: Run focused deterministic verification**

Run: `swift test --filter 'SourceQueryScopeTests|SourceAccessRetrievalTests|ConnectorAdversarialE2ETests|StreamingChatResponderTests|HybridEvidenceRetrieverTests|ChatCitationCardTests'`

Expected: zero failures.

- [x] **Step 2: Run the full deterministic suite**

Run: `swift test`

Expected: zero failures; live-only tests skip without `MACBRAIN_LIVE_OLLAMA=1`.

- [x] **Step 3: Run the relevant Thread Sanitizer pass**

Run: `swift test --sanitize=thread --filter 'ConnectorAdversarialE2ETests|StreamingChatResponderTests|ProductionPromptBarrageTests'`

Expected: zero test failures and no reported data races.

- [x] **Step 4: Run live verification and app verification**

Run the live command from Task 5, then run `./script/build_and_run.sh --verify`.

Expected: live matrix passes and the app launches without stealing foreground focus.

- [x] **Step 5: Update the evidence reports**

Record exact test counts, connector/dimension matrix counts, live outcome counts, sanitizer result, discovered defects, fixes, and any connector that could not be exercised. Never label unavailable external permission state as passed.

- [x] **Step 6: Perform the completion audit**

Map facts, source type, citations, freshness, permissions, and cross-source isolation for each of the eleven connector kinds to named current tests and command output. Keep the goal active if any of the 66 connector/dimension cells lacks direct evidence.
