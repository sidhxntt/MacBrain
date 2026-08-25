# MacBrain beta release guide

## Setup and hardware

MacBrain supports macOS 14+ on Apple silicon. For the default local models, use 16 GB unified memory and keep at least 12 GB free disk space. `qwen3:8b` uses about 5.2 GB storage and 8 GB memory; `nomic-embed-text` uses about 0.3 GB storage and 1 GB memory. Ollama runs on the same Mac; no hosted AI API is required.

Prompts, evidence, embeddings, conversations, memories, source configuration, and response cache stay on-device. Inference is limited to `127.0.0.1`, `localhost`, and `::1`. Diagnostics record coarse event type, connector kind, count, and status only—never source content, prompts, answers, embeddings, bookmarks, or credentials.

## Build, sign, and validate

1. Run `make test` and `make build`.
2. Install a **Developer ID Application** certificate in the login keychain.
3. Run `make release SIGNING_IDENTITY='Developer ID Application: Your Team'`.
4. Notarize and staple `dist/MacBrain.app` using the team’s existing `notarytool` keychain profile, then run `REQUIRE_NOTARIZATION=1 NOTARY_PROFILE=your-profile make release-check`.

The release workflow signs with hardened runtime and `release/MacBrain.entitlements`, and verifies signature, sandbox entitlement, bundle structure, and every permission explanation. It never prints credentials.

## Privacy, deletion, and recovery

Folders and repositories are selected in the system picker and stored as security-scoped bookmarks. There is no whole-disk or home-directory scan. Deleting a source cascades to its configuration, documents, chunks, full-text rows, embeddings, and queued jobs. Memories can be exported, forgotten individually, or deleted in bulk; chats can be deleted from the sidebar.

For complete removal: quit MacBrain, remove `~/Library/Application Support/MacBrain/`, then run `make stop PERMISSION_RESET=1`. This removes the database, source bookmarks/configuration, chats, memories, response cache, and local index. Ollama owns model storage, so remove models separately with `ollama rm <model>` if required.

- **Ollama unavailable:** start Ollama, then refresh Settings.
- **Model missing:** download it in Settings or choose a smaller compatible model.
- **Source unavailable:** reselect the source or grant the named macOS permission; MacBrain never substitutes a broad scan.
- **Interrupted sync:** reopen the app; only changed files are scanned.
- **Migration failure:** preserve Application Support, quit, and remove only `macbrain.sqlite` to create a fresh local index. Do not delete source files.

## Clean-machine beta acceptance

On a fresh macOS account: install the signed app; start Ollama; download both defaults; select one folder; exclude one child path; index a text file; ask a cited question; and open the citation. On a second display, show and dismiss the sidebar. Delete the source, memories, and chat; perform the complete-removal steps; relaunch; and confirm no local records remain. Repeat with Ollama stopped and a missing model: both must show a local recovery action.

Known limitations: live Ollama depends on local installation; Messages and Books can require Full Disk Access and may be unavailable in the sandboxed beta; original photo/video media is never indexed; citation opening requires the original source to remain present and authorized; notarization needs Apple Developer credentials held by the release team.
