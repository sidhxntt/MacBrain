# Privacy and permissions

## Local-first is an architectural constraint

NotchBrain has no product-operated user-data backend and no hosted model default. Local SQLite stores connected source state, chunks, embeddings, sessions, citations, settings, and memories. Ollama receives an assembled local request only when the user invokes a model answer. Local does not mean permission-free: macOS APIs, selected folders, browser/profile paths, and automation remain genuine access boundaries.

## Consent and control

A new install connects no source. Each connector has an explicit configuration and health state; users can inspect it, pause it, reauthorize it, or delete its local index. Selecting one source does not authorize a broad disk scan, live clipboard collection, screen capture, or unrelated app access. Context attachments are visible before send, bounded, removable, and next-request scoped by default.

## Data handling

| Data class | Local owner | Rule |
| --- | --- | --- |
| Source documents/chunks/embeddings | SQLite source/index records | Searchable only after a verified committed source state. |
| Chat and citations | Local chat session records | Preserve evidence IDs and local metadata for explainability. |
| Explicit memory | Local memory repository | Inspect/edit/export/delete separately from source evidence. |
| Provider configuration/secrets | Settings/secure-storage boundary | Never write secrets or source content to ordinary diagnostics. |
| Request context | Attachment/request state | Visible, bounded, redacted, and removable before sending. |
| Diagnostics | Coarse local logs | Status/timing/error category, not raw source or prompt payload. |

## Permission failure is product state

Denied Automation, Contacts, Photos, Calendar/Reminders, Full Disk Access, Accessibility, folder, or browser access should not disable unrelated search. The connector or live-context capability reports a recoverable health state. Revocation makes the affected source ineligible until reauthorization and a successful sync. Future actions that modify another app, file, or service must show a confirmation card with target, content, and side effect.
