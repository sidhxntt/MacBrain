# First-Run Onboarding and Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a newly installed MacBrain user a truthful local-first setup flow, connect sources directly into immediate verified sync, and prove the entire installed-app journey rather than only seeded retrieval components.

**Architecture:** A small `OnboardingStore` owns first-run state and preferences; SwiftUI renders four focused steps and reuses the existing Ollama/source-management boundaries. The workspace presents onboarding from state, Settings can reopen it, and acceptance uses isolated application data plus real macOS permissions where automation cannot substitute.

**Tech Stack:** Swift 6, SwiftUI on macOS 14+, Combine-compatible `ObservableObject`, Swift Testing for state/domain tests, XCTest only for UI automation, existing Ollama and connector services.

---

### Task 1: Add persistent, testable onboarding state

**Files:**
- Create: `Sources/MacBrain/Models/OnboardingStep.swift`
- Create: `Sources/MacBrain/Stores/OnboardingStore.swift`
- Create: `Tests/MacBrainTests/OnboardingStoreTests.swift`

- [ ] **Step 1: Write failing state-transition tests**

```swift
import Foundation
import Testing
@testable import MacBrain

@MainActor
struct OnboardingStoreTests {
    @Test func freshInstallPresentsFirstStep() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = OnboardingStore(defaults: defaults)
        #expect(store.isPresented)
        #expect(store.step == .introduction)
    }

    @Test func limitedCompletionPersistsAndCanBeReopened() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let store = OnboardingStore(defaults: defaults)
        store.complete(mode: .limited)
        #expect(!store.isPresented)
        #expect(OnboardingStore(defaults: defaults).completionMode == .limited)
        store.reopen()
        #expect(store.isPresented)
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter OnboardingStoreTests`

Expected: onboarding types are missing.

- [ ] **Step 3: Implement explicit state**

```swift
enum OnboardingStep: Int, CaseIterable, Sendable {
    case introduction
    case localAI
    case sources
    case ready
}

enum OnboardingCompletionMode: String, Sendable {
    case configured
    case limited
}

@MainActor
final class OnboardingStore: ObservableObject {
    @Published var step: OnboardingStep = .introduction
    @Published private(set) var isPresented: Bool
    private(set) var completionMode: OnboardingCompletionMode?
    private let defaults: UserDefaults

    private enum Key {
        static let completionMode = "com.macbrain.onboarding.completion-mode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completionMode = defaults.string(forKey: Key.completionMode)
            .flatMap(OnboardingCompletionMode.init(rawValue:))
        isPresented = completionMode == nil
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func complete(mode: OnboardingCompletionMode) {
        completionMode = mode
        defaults.set(mode.rawValue, forKey: Key.completionMode)
        isPresented = false
    }

    func reopen() {
        step = .introduction
        isPresented = true
    }
}
```

Use namespaced preference keys and persist only completion state/step, never connector content.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: fresh, completion, relaunch, navigation, and reopen tests pass.

### Task 2: Define truthful onboarding presentation data

**Files:**
- Create: `Sources/MacBrain/Models/OnboardingPresentation.swift`
- Create: `Tests/MacBrainTests/OnboardingPresentationTests.swift`

- [ ] **Step 1: Write failing copy/capability tests**

Assert all four steps have a title, concise explanation, system symbol, primary action, accessibility summary, and no cloud/privacy overclaim. Ready-step examples must be derived from verified source health and available system capabilities, never unavailable sources.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter OnboardingPresentationTests`

Expected: presentation model is missing.

- [ ] **Step 3: Add pure presentation mapping**

Define `OnboardingPagePresentation` and `OnboardingReadySummary`. Map connector presentation states into ready, empty, syncing, permission-needed, optional, and failed groups. Generate examples such as “How many notes do I have?” only when Notes is verified, and always allow safe system examples such as RAM/storage/specifications.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: content, privacy, state grouping, and example-selection tests pass.

### Task 3: Build the native four-step SwiftUI flow

**Files:**
- Create: `Sources/MacBrain/Views/MacBrainOnboardingView.swift`
- Create: `Sources/MacBrain/Views/OnboardingIntroductionView.swift`
- Create: `Sources/MacBrain/Views/OnboardingSourcesView.swift`
- Create: `Sources/MacBrain/Views/OnboardingReadyView.swift`
- Modify: `Sources/MacBrain/Views/OllamaSetupView.swift`

- [ ] **Step 1: Add a construction/accessibility smoke test**

Create an `@MainActor` test that constructs each step with fixed stores and verifies the pure presentation model supplies the accessibility label and actions. SwiftUI UI behavior remains for UI automation/manual acceptance.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter OnboardingPresentationTests`

Expected: onboarding views are missing from the construction test.

- [ ] **Step 3: Implement the four pages**

Use `NavigationStack`, semantic colors/materials already used by MacBrain, a 4/8-point spacing grid, standard controls, keyboard/default actions, and reduced-motion support.

- Introduction: local-only explanation and explicit consent boundary.
- Local AI: embed/reuse `OllamaSetupView`; allow continue when unavailable because lexical/structured/system fallback remains usable.
- Sources: reuse source connector descriptions/actions and display live verified state; do not duplicate connector logic or request a permission before the user selects that connector.
- Ready: show searchable, empty, syncing, and attention states plus capability-derived example questions.

Provide Back, Continue, Continue with limited context, and Finish actions. Never display source content in onboarding progress.

- [ ] **Step 4: Run construction tests and build**

Run:

```sh
swift test --filter 'OnboardingStoreTests|OnboardingPresentationTests'
swift build
```

Expected: tests and macOS build pass without warnings introduced by the new views.

### Task 4: Present onboarding on first launch and reopen it from Settings

**Files:**
- Modify: `Sources/MacBrain/App/AppCoordinator.swift`
- Modify: `Sources/MacBrain/Views/MacBrainWorkspaceView.swift`
- Modify: `Sources/MacBrain/Views/MacBrainPreferencesView.swift`
- Modify: `Tests/MacBrainTests/MacBrainWorkspaceViewTests.swift`

- [ ] **Step 1: Write failing composition tests**

Construct an `AppCoordinator` with isolated defaults. Assert fresh state is presented, configured/limited completion suppresses automatic presentation on relaunch, and Settings `reopen` restores it without clearing connector data.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'OnboardingStoreTests|MacBrainWorkspaceViewTests'`

Expected: coordinator/workspace do not own onboarding state.

- [ ] **Step 3: Wire one shared store**

Add `let onboardingStore: OnboardingStore` to `AppCoordinator`. Observe it in `MacBrainWorkspaceView` and present `MacBrainOnboardingView` as a non-dismissable-by-accident first-run sheet while still providing explicit limited completion. Add “Run Setup Again” to Settings. Do not recreate `SourceLibraryStore` or `InferenceStore`; onboarding receives the shared instances so connection starts the normal immediate sync path.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command. Expected: composition and persistence tests pass.

### Task 5: Add fresh-install end-to-end acceptance harnesses

**Files:**
- Create: `Tests/MacBrainTests/FreshInstallConnectorE2ETests.swift`
- Create: `Tests/MacBrainTests/FreshInstallSystemE2ETests.swift`
- Modify: `Tests/MacBrainTests/ConnectorAdversarialE2ETests.swift`

- [ ] **Step 1: Write an isolated app-dependency fixture**

Create temporary SQLite, legacy snapshot, defaults suite, fixed connector, controlled clock, provider probe, and fixed system-facts provider. Compose the same repository/coordinator/scheduler/planner/responder graph as `AppCoordinator`.

- [ ] **Step 2: Add the no-source-edit journey**

```swift
@Test func freshInstallConnectSyncAskRequiresNoSourceMutation() async throws {
    let app = try await FreshInstallFixture.make()
    #expect(await app.repository.allRecords().isEmpty)
    try await app.connect(.appleNotes, documents: [app.preexistingNote])
    #expect(await app.health(.appleNotes).isSearchable)
    let answer = try await app.ask("Who owns the preexisting Aurora decision?")
    #expect(answer.contains("Riya"))
    #expect(answer.contains("[S1]"))
    #expect(await app.connector.mutationCount == 0)
}
```

Add verified empty, count, restart, 300-second refresh, refresh-while-chatting, refresh failure isolation, permission revoke, deletion, and semantic-timeout cases.

- [ ] **Step 3: Add broad system journey cases**

Ask installed/current RAM, available storage, full specifications, macOS, uptime, battery, apps, network, displays, and unsupported maximum wording through the production responder graph. Assert dynamic facts are sampled for every request and no provider call is needed for direct facts.

- [ ] **Step 4: Run focused E2E tests**

Run:

```sh
swift test --filter 'FreshInstallConnectorE2ETests|FreshInstallSystemE2ETests|ConnectorAdversarialE2ETests'
```

Expected: every journey terminates with zero stale, unauthorized, cross-source, or unverified-ready result.

### Task 6: Run build, concurrency, and installed-app verification

**Files:**
- Modify: `Tests/StressTests/test_report.md`
- Modify: `Tests/StressTests/production_chat_acceptance_audit.md`
- Modify: `docs/todos/onboarding.md`

- [ ] **Step 1: Run the full deterministic suite**

Run:

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache \
  swift test
```

Expected: zero failures; opt-in live tests skip explicitly.

- [ ] **Step 2: Run focused Thread Sanitizer**

Run:

```sh
swift test --sanitize=thread --filter 'FreshInstallConnectorE2ETests|ConnectorRefreshSchedulerTests|QueryPlanResponderTests'
```

Expected: zero failures and no race reports.

- [ ] **Step 3: Verify release-style build and launch**

Run:

```sh
swift build -c release
./script/build_and_run.sh --verify
```

Expected: app builds and launches without blocking or stealing unintended focus.

- [ ] **Step 4: Run real local-model verification when Ollama is available**

Run:

```sh
env MACBRAIN_LIVE_OLLAMA=1 \
  CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-module-cache \
  SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache \
  swift test --filter OllamaLiveIntegrationTests
```

Expected: live connector fact/citation cases pass; if Ollama is unavailable, report the external prerequisite as unverified rather than passed.

- [ ] **Step 5: Perform the real permission/manual pass**

Using an isolated app-data directory or clean test account:

1. launch and complete/skip onboarding;
2. connect Apple Notes without editing a note;
3. wait for verified ready/empty-ready;
4. ask a natural content question and “How many notes do I have?”;
5. chat while a manual/automatic refresh runs;
6. restart and query again;
7. revoke permission and verify immediate exclusion after revalidation;
8. ask RAM, storage, and specification questions and compare with macOS.

- [ ] **Step 6: Update evidence documents accurately**

Record command output, test counts, installed-app observations, permission states, Ollama availability, and any remaining unverified item. Mark completed onboarding checklist items only when their behavior is present. Do not use synthetic tests as evidence for real macOS permission prompts.

### Task 7: Perform requirement-by-requirement completion audit

**Files:**
- Modify: `Tests/StressTests/production_chat_acceptance_audit.md`

- [ ] **Step 1: Map every product requirement to authoritative evidence**

Create an audit table covering fresh install, onboarding, one-time connection, no source mutation, immediate sync, verified readiness, empty source, 300-second concurrent refresh, UI responsiveness, open-ended connector prompts, counts/date queries, lexical timeout fallback, system domains, restart repair, authorization/removal isolation, citations, cache revisions, and privacy.

- [ ] **Step 2: Inspect rather than infer completion**

For every row, cite a named passing test, current command output, or real runtime observation. Treat missing, indirect, synthetic-only, skipped, or stale evidence as not achieved and continue implementation/verification.

- [ ] **Step 3: Close only after every row is proved**

Run `git diff --check`, inspect the final worktree without reverting user-owned changes, and repeat the full relevant verification after the final edit. Completion requires no remaining required row marked missing or unverified.
