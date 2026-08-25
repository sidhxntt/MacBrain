# Folder and Git Connectors Design

## Goal

Replace the single-file Transcript connector with explicit recursive Folder indexing. Extend Git repositories with recursive content from tracked supported files plus repository metadata.

## Behavior

- Folder selection grants access only to that selected tree.
- Folder sync recursively indexes readable text, caption, Markdown, PDF, source-code, config, and extensionless text files, including hidden and secret files.
- Folder sync excludes only dependency and build folders; hidden files, Git internals, `.env` files, credentials, and keys remain eligible when readable and supported.
- Re-sync replaces that source's indexed file set, so added, changed, and deleted files are reflected locally.
- Git sync reads the full selected working tree of supported files, including hidden and secret files, excluding only dependency and build folders. It also adds branch, commit, author, timestamp, changed-file, and tracked/untracked metadata.
- Existing persisted `transcript` records decode as Folder records. Existing selected files remain readable for backwards compatibility, while no Transcript connector is offered in the UI.

## Privacy

No connector is created or scanned until the user selects it and confirms. Folder and Git selections persist security-scoped bookmarks. Content remains local and per-source deletion removes connector configuration and documents.
