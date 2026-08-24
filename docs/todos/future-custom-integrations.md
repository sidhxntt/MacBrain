# Future custom app integrations roadmap

## Decision

Custom integrations are feasible but not current work. They must extend MacBrain's explicit local-connector model: no cloud relay, no silent data access, and no active connector until user installs, configures, and confirms it.

## Possible connector types

1. **File-based** — user selects a folder, database, export, or package; MacBrain indexes only that scoped location.
2. **Apple Events / Automation** — documented scripting dictionaries, Shortcuts, or App Intents with exact target-app permission.
3. **Local API** — user-enabled localhost API, Unix socket, or app extension with local authentication only.
4. **Plugin / extension** — signed plugin emits validated documents over an authenticated local channel.

## Required connector contract

- [ ] Signed manifest with identity, version, capabilities, privacy disclosure, settings, deletion behavior.
- [ ] Configure user-selected account, folder, workspace, or scope.
- [ ] Authorize only required macOS/app permission.
- [ ] Initial and incremental sync supporting creates, updates, deletes, pause/resume, delete, health.
- [ ] Normalized documents with stable source/item IDs, text, timestamps, metadata, content hash, optional deep link.

## Manifest and SDK

- [ ] Define signed manifest fields: identity, requested capabilities, data categories, retention, sync modes, schema.
- [ ] Publish Swift SDK for protocols, validation, checkpoints, logging, cancellation, fixtures.
- [ ] Prevent plugins from accessing MacBrain database or other connector scopes.

## Lifecycle and security

- [ ] User reads disclosure, chooses scope, and confirms before first sync.
- [ ] Validate manifest and permission; retain local checkpoint after initial sync.
- [ ] Refresh only while MacBrain is open, on declared interval or local change signal.
- [ ] Show health, last success, changes, and actionable errors.
- [ ] Store credentials/bookmarks in Keychain or scoped storage, never chat data/logs.
- [ ] Validate schema, paths, MIME types, response size; rate/time-limit work; cancel on pause, deletion, quit.
- [ ] Require separate confirmation for any write/action capability.

## Delivery phases

### A — first-party foundation

- [ ] Stabilize connector document, checkpoint, health, pause, delete, and activity models.
- [ ] Add capability declarations and source disclosures.

### B — local SDK

- [ ] Publish protocol package, manifest schema, fixture runner, validator, conformance tests.
- [ ] Build file-export, Apple Events, and localhost API samples.

### C — trusted custom connectors

- [ ] Signed bundles, install/review UI, isolation where feasible.
- [ ] Add compatibility, crash isolation, upgrade, rollback, diagnostics.

### D — optional actions

- [ ] Support declared App Intents, Shortcuts, or documented APIs.
- [ ] Preview action target/parameters and require confirmation by default.

## Non-goals

- No universal scraper for arbitrary app memory, protected databases, or network traffic.
- No bypassing TCC, Full Disk Access, sandboxing, encryption, or macOS protections.
- No cloud marketplace, remote code execution, or remote connector data pipeline.
- No silent third-party actions from chat context.
