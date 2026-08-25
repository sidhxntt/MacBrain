# Hybrid change detection

## Goal

Keep local context current without repeatedly rebuilding unchanged indexes or polling the entire Mac too aggressively.

## Target model

- [ ] **Folders and Git repositories:** use macOS filesystem events to notice creates, edits, moves, and deletions quickly; debounce bursts for 1–3 seconds before processing affected paths.
- [ ] **App libraries and browser profiles:** use a reliable app-specific change signal when one exists; otherwise retain a scheduled refresh.
- [ ] **Safety scan:** run a low-frequency reconciliation scan (for example, every few hours) to recover from missed events, sleep/wake transitions, or external-volume changes.
- [ ] **Incremental indexing:** compare stable source IDs, content hashes, timestamps, and deletion state. Reuse unchanged stored documents/chunks; add, replace, or remove only affected items.
- [ ] **User visibility:** show concise source status and last successful refresh in Sync activity, without exposing private content.

## Current behavior

MacBrain refreshes connected sources every five minutes while it is open. The refresh detects additions, modifications, and deletions. Unchanged documents retain their stored index entries and are not rebuilt.

## Guardrails

- [ ] Never watch or index a location outside the connector scope selected by the user.
- [ ] Respect pause, delete, permission changes, external-drive availability, and app termination.
- [ ] Do not use filesystem events as the sole correctness mechanism; retain the safety scan.
- [ ] Keep connector permissions persistent through normal macOS TCC behavior; only request again after macOS revokes/resets permission or the app identity changes.
