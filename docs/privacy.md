# Notch Brain Privacy and Security Contract

## Defaults

- All indexing, embeddings, retrieval, conversations, and memories are local.
- No hosted model, analytics backend, or user-data server is required.
- The app never silently indexes the whole Mac or broad home-directory paths.
- Ollama receives only the prompt and evidence explicitly assembled for the current request.
- Network access is limited to explicitly enabled model setup/provider operations.

## Consent and permissions

Users select folders, files, and repositories to index. Each source shows what will be read, where it will be stored, and how to remove it. Clipboard, selected text, Accessibility, screen capture, and automation permissions are opt-in, explained in plain language, and independently disableable. Denial must leave the rest of the app usable.

Context capture is explicit, visible, scoped to the next request by default, bounded in size, and removable before submission. No continuous screen, keystroke, clipboard, browser, or editor collection is allowed in the MVP.

## Exclusions and sensitive data

Default exclusions include credentials, SSH keys, environment files, token/config directories, build products, dependency caches, generated binaries, and user-configured paths. A connector must preserve exclusions during discovery and re-indexing. Redaction occurs before prompt assembly and logs.

## Retention and deletion

Users can inspect indexed sources, delete a source, remove its documents/chunks/embeddings, clear conversations, edit/delete individual memories, delete all memories, and export memories. Deletion removes retrieval eligibility and durable local records; temporary in-flight buffers are discarded on cancellation or completion. Indexed source content and assistant-created memories are always displayed as different categories.

## Secrets and logs

Provider tokens and settings that are secrets belong in Keychain. Source content, prompts, responses, embeddings, file contents, clipboard text, and personal identifiers must not enter ordinary logs or crash metadata. Diagnostics contain event type, timing, coarse status, and redacted error codes only, and are local unless the user explicitly exports them.

## External actions

Read-only source opening may happen immediately. Any action that writes to a file, calendar, reminder, email, GitHub, or other external system requires a reviewable confirmation showing target, content, and side effect. External actions are post-MVP.

## Privacy acceptance tests

- A new install indexes nothing until a source is selected.
- Disabled context providers contribute no data.
- Excluded files never appear in the index or prompt.
- Deleting a source removes it from search and citations.
- Forgetting a memory removes it from memory retrieval.
- Ollama request fixtures contain only assembled, authorized content.
- Logs remain content-free under indexing, retrieval, generation, and failure tests.
