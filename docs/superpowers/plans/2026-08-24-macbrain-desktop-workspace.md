# MacBrain Desktop Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MacBrain launch as a standard macOS chat workspace while preserving its existing optional overlay sidebar.

**Architecture:** `AppCoordinator` owns shared chat and source stores. A `WindowGroup` hosts a navigation-split desktop UI and passes those stores to both desktop and overlay surfaces. Existing chat components remain the single source for the message, SVG, header, welcome, and composer UI.

**Tech Stack:** Swift 6, SwiftUI, AppKit panels, SwiftPM, XCTest.

---

### Task 1: Prove desktop application policy

**Files:**
- Modify: `Tests/MacBrainTests/OverlayWindowPolicyTests.swift`
- Modify: `Sources/MacBrain/Services/OverlayWindowPolicy.swift`

- [ ] **Step 1: Write failing test**

```swift
func testDesktopAppUsesRegularActivationPolicy() {
    XCTAssertEqual(OverlayWindowPolicy.applicationActivationPolicy, .regular)
}
```

- [ ] **Step 2: Verify failure**

Run: `make test`

Expected: failure because policy is `.accessory`.

- [ ] **Step 3: Implement minimal policy change**

```swift
static let applicationActivationPolicy: NSApplication.ActivationPolicy = .regular
```

- [ ] **Step 4: Verify passing test**

Run: `make test`

Expected: policy test passes.

### Task 2: Model desktop navigation

**Files:**
- Create: `Sources/MacBrain/Models/MainWorkspaceSection.swift`
- Create: `Sources/MacBrain/Stores/MainWorkspaceStore.swift`
- Create: `Tests/MacBrainTests/MainWorkspaceStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
@MainActor
final class MainWorkspaceStoreTests: XCTestCase {
    func testStartsOnChats() {
        XCTAssertEqual(MainWorkspaceStore().selection, .chats)
    }

    func testSidebarRequestIsOffUntilUserEnablesIt() {
        let store = MainWorkspaceStore()
        XCTAssertFalse(store.isSidebarEnabled)
        store.enableSidebar()
        XCTAssertTrue(store.isSidebarEnabled)
    }
}
```

- [ ] **Step 2: Verify failure**

Run: `make test`

Expected: compilation fails because `MainWorkspaceStore` does not exist.

- [ ] **Step 3: Implement model and store**

```swift
enum MainWorkspaceSection: Hashable, CaseIterable, Identifiable {
    case chats, sources, preferences
    var id: Self { self }
}

@MainActor
final class MainWorkspaceStore: ObservableObject {
    @Published var selection: MainWorkspaceSection = .chats
    @Published private(set) var isSidebarEnabled = false
    func enableSidebar() { isSidebarEnabled = true }
}
```

- [ ] **Step 4: Verify passing tests**

Run: `make test`

Expected: new store tests pass.

### Task 3: Share app state with desktop and overlay

**Files:**
- Modify: `Sources/MacBrain/App/AppCoordinator.swift`
- Modify: `Sources/MacBrain/Services/SidebarPanelController.swift`
- Create: `Tests/MacBrainTests/SidebarPanelControllerTests.swift`

- [ ] **Step 1: Write failing injection test**

```swift
@MainActor
func testSidebarControllerUsesInjectedChatStore() {
    let store = ChatStore()
    let controller = SidebarPanelController(chatStore: store)
    XCTAssertTrue(controller.chatStore === store)
}
```

- [ ] **Step 2: Verify failure**

Run: `make test`

Expected: controller has no `chatStore:` initializer.

- [ ] **Step 3: Implement shared ownership**

```swift
let chatStore: ChatStore
let sourceLibrary: SourceLibraryStore
let workspaceStore = MainWorkspaceStore()

func openSidebar() {
    workspaceStore.enableSidebar()
    activationBarController?.hide()
    sidebarController?.focus()
}
```

Pass `chatStore` into `SidebarPanelController`; expose it at module scope for the injection test and remove internal `ChatStore` creation. `start()` creates controllers and source synchronization but does not show activation bar until `openSidebar()` is called.

- [ ] **Step 4: Verify passing tests**

Run: `make test`

Expected: shared-store test and existing chat tests pass.

### Task 4: Add standard desktop scenes

**Files:**
- Modify: `Sources/MacBrain/App/MacBrainApp.swift`
- Create: `Sources/MacBrain/Views/MacBrainWorkspaceView.swift`
- Create: `Sources/MacBrain/Views/MacBrainWorkspaceSidebar.swift`
- Create: `Sources/MacBrain/Views/MacBrainChatWorkspaceView.swift`
- Create: `Sources/MacBrain/Views/MacBrainPreferencesView.swift`

- [ ] **Step 1: Write failing scene compile test**

```swift
func testDesktopWorkspaceCanBeConstructed() {
    _ = MacBrainWorkspaceView(coordinator: AppCoordinator())
}
```

- [ ] **Step 2: Verify failure**

Run: `make test`

Expected: compilation fails because `MacBrainWorkspaceView` does not exist.

- [ ] **Step 3: Implement main scene**

```swift
WindowGroup("MacBrain") {
    MacBrainWorkspaceView(coordinator: appDelegate.coordinator)
        .frame(minWidth: 960, minHeight: 680)
}
Settings {
    MacBrainPreferencesView(coordinator: appDelegate.coordinator)
}
```

Use `NavigationSplitView` with `.chats`, `.sources`, and `.preferences`. Reuse `ChatNavigationBar`, `ChatConversationView`, `ChatComposer`, `MacBrainWelcomeView`, and `SourceManagerView`. The chat detail uses source manager as a sheet from the existing composer. Toolbar actions call `chatStore.startNewChat()` and `coordinator.openSidebar()`.

- [ ] **Step 4: Verify passing tests and compile**

Run: `make test && make build`

Expected: all tests pass and `dist/MacBrain.app` is created.

### Task 5: Verify native behavior and preserve overlay

**Files:**
- Modify: `Sources/MacBrain/App/AppCoordinator.swift` only if verification exposes lifecycle issue
- Modify: `Sources/MacBrain/Views/MacBrainWorkspaceView.swift` only if verification exposes layout issue

- [ ] **Step 1: Launch packaged app**

Run: `make start`

Expected: MacBrain opens a regular foreground window with Dock presence, desktop workspace visible, and no activation handle until sidebar is opened.

- [ ] **Step 2: Manually verify core flows**

1. Create a chat from desktop navigation and see its tab and messages.
2. Open Sources and Preferences from navigation.
3. Select `Open Sidebar` from toolbar.
4. Verify sidebar shows the same active tab/message state.
5. Hide sidebar and confirm main window remains open.

- [ ] **Step 3: Run final verification**

Run: `make test && make build`

Expected: full test suite passes and packaged app builds without compile errors.
