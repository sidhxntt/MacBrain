# MacBrain Desktop Workspace Design

## Goal

Launch MacBrain as a standard macOS chat application while retaining its existing always-on-top sidebar as an optional mode.

## Product Shape

MacBrain opens a regular foreground macOS window with Dock presence and standard window controls. Its primary layout follows the approved reference: a native left navigation column, a central chat workspace, and a bottom composer.

The sidebar remains available from an explicit `Open Sidebar` action in the main window and Preferences. It is not shown automatically on app launch. Enabling it preserves its current activation handle and overlay behavior.

## Architecture

`AppCoordinator` becomes app-wide owner of one `ChatStore` and one `SourceLibraryStore`. Both the desktop workspace and sidebar receive those same instances, so chats, tabs, messages, greetings, and enabled sources stay synchronized whichever surface the user uses.

`MacBrainApp` owns a `WindowGroup` for the primary workspace and a non-empty `Settings` scene. Application activation changes from accessory to regular. Overlay panels continue using their existing AppKit controllers and high window levels.

The desktop shell is split into small SwiftUI views: main navigation, chat workspace, and preferences. Existing conversation, composer, tab, welcome, and source-manager components are reused rather than copied.

## Main Window

### Left navigation

- Brand: MacBrain.
- Primary action: New Chat.
- Destinations: Chats, Sources, Preferences.
- Recent chat sessions below destinations.
- Sidebar selection changes detail content without losing chat state.

### Chat workspace

- Native toolbar exposes active title, history, new chat, and `Open Sidebar`.
- Existing chat tabs, conversation, welcome state, privacy message, and composer remain functionally consistent with sidebar UI.
- New chats created from either surface appear in both immediately.

### Sources and Preferences

- Sources shows existing local source management UI.
- Preferences includes a clear sidebar action, a local-only privacy summary, and an entry point to source management.
- The dedicated macOS Settings scene presents the same preferences content.

## Visual Treatment

- Native `NavigationSplitView`, toolbar, settings, and semantic SwiftUI colors.
- System material and existing adaptive glass only on product-specific surfaces.
- No custom opaque paint over system sidebar or toolbar.
- Standard Mac pointer, keyboard, focus, accessibility, resize, and state-restoration behavior.

## Error and Edge Behavior

- If sidebar cannot obtain a screen, main workspace remains usable and sidebar action fails safely.
- Closing or hiding sidebar never closes desktop workspace.
- App termination stops overlay controllers. Local connectors sync only after a user explicitly connects or manually syncs one.
- Existing local-only source behavior remains unchanged; this work does not expand data collection.

## Tests

- Test regular application activation policy for primary desktop launch.
- Test desktop navigation defaults to chat and sidebar request changes only sidebar availability.
- Test shared store injection so desktop and sidebar use same session state.
- Run complete Swift test suite, package `.app`, and launch the bundle for manual layout verification.

## Scope Boundaries

This work does not alter RAG indexing, connector permissions, source scanning, chat-model behavior, or overlay interaction mechanics beyond passing shared app state and making sidebar opt-in.
