# Notch Brain Privacy and Security Contract

## Defaults

- All indexing, embeddings, retrieval, conversations, and memories are local.
- No hosted model, analytics backend, or user-data server is required.
- The app never performs a general whole-Mac or home-directory disk scan. It offers supported local connectors, but reads nothing until the user explicitly selects a connector and grants any required macOS permission.
- Ollama receives only the prompt and evidence explicitly assembled for the current request.
- Network access is limited to explicitly enabled model setup/provider operations.

## Consent and permissions

Users explicitly select every Apple productivity connector, browser profile, folder, file, and repository to index. Selecting a connector requests only its applicable macOS permission. A successful connection immediately scans and atomically commits the source's current content; the user does not need to edit an item to prove the connection. Each source shows what will be read, whether its committed index is ready, where it is stored, and how to remove it. Clipboard, selected text, Accessibility, screen capture, and automation permissions are opt-in, explained in plain language, and independently disableable. Denial must leave the rest of the app usable.

Context capture is explicit, visible, scoped to the next request by default, bounded in size, and removable before submission. No continuous screen, keystroke, clipboard, browser, or editor collection is allowed in the MVP.

## Local source connectors

MacBrain connects a source only after the user selects it and confirms its consent flow. The first successful connection immediately indexes the source's existing content and marks it searchable only after a complete source generation has been committed. While MacBrain is running, each connected source is refreshed approximately every five minutes. Concurrent refresh requests share the same committed result, and queries continue to use the last verified generation until a replacement is committed. It remains local-only and does not send source content to a cloud service.

- **Apple Notes:** opt-in. MacBrain asks macOS for Automation access and then indexes Notes accounts and folders available on this Mac.
- **Apple Mail:** opt-in. MacBrain asks macOS for Automation access and then indexes locally available Mail accounts and mailboxes, preserving sender, recipients, subject, sent date, Mail message/thread identifier, and source provenance.
- **Apple Calendar:** opt-in. MacBrain requests Calendar access and indexes events across local calendars.
- **Apple Reminders:** opt-in. MacBrain requests Reminders access and indexes lists, completion state, due dates, and notes.
- **Apple Contacts:** opt-in. MacBrain requests Contacts access and indexes names, organization, role, email, phone, and web-address fields; it does not read contact notes.
- **Browser Profiles:** disabled until you explicitly select **Browser Profiles** and confirm. MacBrain then discovers known, supported local profile roots for installed browsers and keeps only those selected browser profiles in its local refresh loop. It does not enable unrelated application integrations.
- **Messages:** opt-in. MacBrain indexes local message text and conversation provenance. macOS may require Full Disk Access.
- **Photos metadata:** opt-in. MacBrain requests Photos access and indexes metadata such as media type, dates, dimensions, favorite status, and available location; it does not copy original photo or video files.
- **Apple Books:** opt-in. MacBrain indexes locally stored book title, author, and library-path metadata. macOS may require Full Disk Access.
- **Meeting transcripts:** user explicitly chooses one `.txt`, `.md`, `.srt`, or `.vtt` file. Caption timestamps are discarded before search.
- **Git repositories:** user explicitly chooses one local repository. MacBrain reads local branches and selected commit range metadata, including authors, changed files, and issue or pull-request references found in commit subjects.

Each source shows its health, item count, last successful sync, and permission failure state. A connected source is queryable only when its local SQLite index records a verified committed generation or a verified empty result. On restart, that database state remains authoritative. Pausing retains already indexed local content but blocks future syncs. If permission is revoked, the source is excluded from retrieval until reauthorization and a successful sync. Reauthorization retries the same source. Deleting a source removes its configuration and all indexed documents from local retrieval; stale legacy state cannot recreate it.

## Exclusions and sensitive data

Default exclusions include credentials, SSH keys, environment files, token/config directories, build products, dependency caches, generated binaries, and user-configured paths. A connector must preserve exclusions during discovery and re-indexing. Redaction occurs before prompt assembly and logs.

## Retention and deletion

Users can inspect indexed sources, delete a source, remove its documents/chunks/embeddings, clear conversations, edit/delete individual memories, delete all memories, and export memories. Deletion removes retrieval eligibility and durable local records; temporary in-flight buffers are discarded on cancellation or completion. Indexed source content and assistant-created memories are always displayed as different categories.

## Secrets and logs

Provider tokens and settings that are secrets belong in Keychain. Source content, prompts, responses, embeddings, file contents, clipboard text, and personal identifiers must not enter ordinary logs or crash metadata. Diagnostics contain event type, timing, coarse status, and redacted error codes only, and are local unless the user explicitly exports them.

## External actions

Read-only source opening may happen immediately. Any action that writes to a file, calendar, reminder, email, GitHub, or other external system requires a reviewable confirmation showing target, content, and side effect. External actions are post-MVP.

## Privacy acceptance tests

- A new install reads no connector data until the user explicitly selects a source and grants its required permission.
- Connecting a populated source indexes its existing content immediately without requiring the user to edit an item.
- A source becomes queryable only after a verified generation or verified empty result is committed, and its committed state survives restart.
- Connected sources refresh approximately every five minutes without exposing a partial replacement generation to chat.
- Disabled context providers contribute no data.
- Excluded files never appear in the index or prompt.
- Deleting a source removes it from search and citations.
- Forgetting a memory removes it from memory retrieval.
- Ollama request fixtures contain only assembled, authorized content.
- Logs remain content-free under indexing, retrieval, generation, and failure tests.
