# Privacy and Permissions

## Local-first is a concrete architecture

MacBrain has no product-operated user-data backend and no hosted AI default. SQLite holds local sources, chunks, embeddings, conversations, citations, settings and memories; Ollama receives only the assembled prompt/evidence for a local request. This does not mean every future connector is permission-free: macOS APIs, explicit folder bookmarks, and user-selected browser/profile paths remain real local access boundaries.

## Consent and control

Every source starts disconnected. The user selects it, receives its native permission request where applicable, can inspect its health/item count/last sync, pause it, reauthorize it, or delete it with associated index records. A new install indexes nothing. Disabled context providers contribute nothing. Source selection is not permission for a general disk scan.

## Data categories and handling

| Data | Normal location | Rule |
| --- | --- | --- |
| Sources/chunks/embeddings | Local SQLite/app storage | Searchable only after a verified committed source generation. |
| Chat/citations | Local session store | Persist evidence IDs and answer metadata for explainability. |
| Explicit memories | Local memory store | Inspect/edit/export/delete; displayed separately from source evidence. |
| Credentials | Keychain | Never ordinary preferences, logs, or repository files. |
| Context | In-memory/local request state | Visible, removable, bounded, redacted, next-request scoped by default. |
| Diagnostics | Local redacted logs | Event/timing/status, never source content or prompt/response text. |

## Permissions and failure behavior

Denied Automation, Contacts, Photos, Calendar/Reminders, Full Disk Access, Accessibility, clipboard, screen capture, or folder access does not disable unrelated sources or search. The UI reports a recoverable health state. Revocation excludes the connector until reauthorization and successful local sync. Future external write actions require a confirmation card showing target, content and side effect.
