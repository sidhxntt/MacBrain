# Notch Brain Privacy and Security Contract

## Defaults

- All indexing, embeddings, retrieval, conversations, and memories are local.
- No hosted model, analytics backend, or user-data server is required.
- The app never performs a general whole-Mac or home-directory disk scan. It automatically offers the supported Apple app connectors and requests each required macOS permission before reading their data.
- Ollama receives only the prompt and evidence explicitly assembled for the current request.
- Network access is limited to explicitly enabled model setup/provider operations.

## Consent and permissions

Users select folders, files, and repositories to index. Apple productivity connectors are created automatically and request their applicable macOS permission at launch. Each source shows what will be read, where it will be stored, and how to remove it. Clipboard, selected text, Accessibility, screen capture, and automation permissions are opt-in, explained in plain language, and independently disableable. Denial must leave the rest of the app usable.

Context capture is explicit, visible, scoped to the next request by default, bounded in size, and removable before submission. No continuous screen, keystroke, clipboard, browser, or editor collection is allowed in the MVP.

## Local source connectors

MacBrain automatically connects the Apple work sources listed below at launch and requests each macOS consent flow when needed. It remains local-only and does not send source content to a cloud service.

- **Apple Notes:** enabled by default. MacBrain asks macOS for Automation access and then indexes Notes accounts and folders available on this Mac.
- **Apple Mail:** enabled by default. MacBrain asks macOS for Automation access and then indexes locally available Mail accounts and mailboxes, preserving sender, recipients, subject, sent date, Mail message/thread identifier, and source provenance.
- **Apple Calendar:** enabled by default. MacBrain requests Calendar access and indexes events across local calendars.
- **Apple Reminders:** enabled by default. MacBrain requests Reminders access and indexes lists, completion state, due dates, and notes.
- **Apple Contacts:** enabled by default. MacBrain requests Contacts access and indexes names, organization, role, email, phone, and web-address fields; it does not read contact notes.
- **Browser Profiles:** disabled until you explicitly select **Browser Profiles** and confirm. MacBrain then discovers known, supported local profile roots for installed browsers and keeps only those selected browser profiles in its local refresh loop. It does not enable unrelated application integrations.
- **Messages:** enabled by default. MacBrain indexes local message text and conversation provenance. macOS may require Full Disk Access.
- **Photos metadata:** enabled by default. MacBrain requests Photos access and indexes metadata such as media type, dates, dimensions, favorite status, and available location; it does not copy original photo or video files.
- **Apple Books:** enabled by default. MacBrain indexes locally stored book title, author, and library-path metadata. macOS may require Full Disk Access.
- **Meeting transcripts:** user explicitly chooses one `.txt`, `.md`, `.srt`, or `.vtt` file. Caption timestamps are discarded before search.
- **Git repositories:** user explicitly chooses one local repository. MacBrain reads local branches and selected commit range metadata, including authors, changed files, and issue or pull-request references found in commit subjects.

Each source shows its health, item count, last successful sync, and permission failure state. Pausing retains already indexed local content but blocks future syncs. Reauthorization retries the same source. Deleting a source removes its configuration and all indexed documents from local retrieval.

## Exclusions and sensitive data

Default exclusions include credentials, SSH keys, environment files, token/config directories, build products, dependency caches, generated binaries, and user-configured paths. A connector must preserve exclusions during discovery and re-indexing. Redaction occurs before prompt assembly and logs.

## Retention and deletion

Users can inspect indexed sources, delete a source, remove its documents/chunks/embeddings, clear conversations, edit/delete individual memories, delete all memories, and export memories. Deletion removes retrieval eligibility and durable local records; temporary in-flight buffers are discarded on cancellation or completion. Indexed source content and assistant-created memories are always displayed as different categories.

## Secrets and logs

Provider tokens and settings that are secrets belong in Keychain. Source content, prompts, responses, embeddings, file contents, clipboard text, and personal identifiers must not enter ordinary logs or crash metadata. Diagnostics contain event type, timing, coarse status, and redacted error codes only, and are local unless the user explicitly exports them.

## External actions

Read-only source opening may happen immediately. Any action that writes to a file, calendar, reminder, email, GitHub, or other external system requires a reviewable confirmation showing target, content, and side effect. External actions are post-MVP.

## Privacy acceptance tests

- A new install creates supported Apple connectors and requests consent before indexing their data; selected files and repositories remain empty until the user adds them.
- Disabled context providers contribute no data.
- Excluded files never appear in the index or prompt.
- Deleting a source removes it from search and citations.
- Forgetting a memory removes it from memory retrieval.
- Ollama request fixtures contain only assembled, authorized content.
- Logs remain content-free under indexing, retrieval, generation, and failure tests.
