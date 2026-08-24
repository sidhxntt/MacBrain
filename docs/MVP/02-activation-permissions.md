# Phase 02 — Global Activation and Permissions

## Goal

Make the sidebar accessible from any application while keeping Accessibility, filesystem, and clipboard access explicit.

## Deliverables

- Configurable global keyboard shortcut.
- Permission status and explanations.
- Clipboard context capture.
- Selected-text capture with fallback behavior.
- Active application/window metadata.

## Implementation sequence

- [ ] Define `GlobalShortcutManager` behind a protocol so registration can be tested without system events.
- [ ] Register a default shortcut and route it to the panel toggle.
- [ ] Implement `PermissionManager` for Accessibility and security-scoped folder access.
- [ ] Show why each permission is needed before requesting it; provide a settings path to retry.
- [ ] Capture clipboard text only when the user enables or explicitly invokes context capture.
- [ ] Capture selected text through Accessibility APIs when permission exists; otherwise offer copy-to-clipboard fallback instructions.
- [ ] Record active application and window title as metadata, not document content.
- [ ] Add tests for registration failure, denied permissions, clipboard size limits, and redaction.

## Exit criteria

The shortcut toggles the panel from other apps, denied permissions produce recovery instructions, and no context is captured or indexed without an explicit user action or setting.
