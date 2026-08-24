# Chatbot Sidebar Design

## Goal

Turn the existing Notch Brain sidebar empty state into a usable local chatbot surface. The first implementation includes the polished UI and a functional mock conversation, without Cloud services, network calls, or third-party dependencies.

## User experience

- Keep the existing always-on-top sidebar, right-edge placement, C-shaped chrome, and slide-in/slide-out transitions.
- Keep the Notch Brain header with expand and close controls.
- Show a centered welcome state when no messages exist.
- Show a scrollable conversation when messages exist.
- Render user and assistant messages as visually distinct bubbles using the existing dark purple glass treatment.
- Add a bottom composer inspired by the reference image:
  - single-line text field optimized for quick desktop prompts;
  - attachment affordance reserved for future local source selection;
  - local-mode label;
  - send button;
  - Return/Enter submission.
- Disable send for whitespace-only input.
- Keep focus in the composer after sending when possible.
- Provide a clear-conversation action in the header or composer menu.

## Architecture

### `ChatMessage`

Small value type containing stable ID, role (`user` or `assistant`), text, and creation date. It remains UI-independent and `Sendable`.

### `ChatStore`

`@MainActor` observable state owner for the sidebar conversation. It owns messages, draft text, sending state, and clear/send operations. It does not know how replies are generated.

### `ChatResponder`

Small async protocol that accepts a user message and returns an assistant message. The initial `LocalMockChatResponder` returns deterministic local responses after a short delay. This boundary allows a future on-device responder or retrieval-backed responder without changing the view.

### SwiftUI views

- `SidebarView`: composition and existing window actions.
- `ChatConversationView`: welcome state, message list, and scroll behavior.
- `ChatMessageBubble`: role-specific message presentation.
- `ChatComposer`: draft editing and send controls.

Keep these components in separate Swift files as they grow. No UIKit or external framework is needed.

## Data flow

1. User types into `ChatComposer`.
2. `ChatStore.sendDraft()` trims and validates text.
3. Store appends the user message and marks sending state.
4. Store calls `ChatResponder` asynchronously.
5. Store appends the local assistant response on the main actor.
6. Conversation scrolls to the newest message.

If the responder throws, the store stops sending state and adds a clear local error message or exposes an error state for the UI. The initial mock responder should not fail unexpectedly.

## Visual treatment

- Follow `build-macos-apps:liquid-glass`: preserve adaptive material, avoid opaque custom chrome, and use standard SwiftUI controls where possible.
- Match the reference hierarchy: quiet header, generous conversation space, prominent rounded composer, restrained accent color, and readable muted secondary text.
- Respect the sidebar's existing flush right edge and left-side rounded corners.
- Keep controls accessible with labels, help text, keyboard focus, Dynamic Type, VoiceOver descriptions, and Reduce Motion behavior.

## Testing

- `ChatStore` appends a user message before the assistant response.
- Whitespace-only drafts do not send.
- Mock responder returns deterministic content.
- Sending state prevents duplicate sends.
- Clear removes all messages and resets draft/sending state.
- Existing sidebar geometry, overlay policy, and activation-bar tests remain green.
- Build and package the macOS `.app` through `script/build_and_run.sh --bundle`.

## Explicit non-goals

- No Cloud integration.
- No network requests.
- No authentication, accounts, sync, or persistence in this pass.
- Attachment button is visual/reserved only until local source indexing is implemented.
- No changes to activation-bar placement or sidebar window z-order.
