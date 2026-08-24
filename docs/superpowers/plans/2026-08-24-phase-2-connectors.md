# Phase 2 — Local Source Connectors

## Goal

Let MacBrain index explicitly selected local work sources and answer from that evidence without a cloud service.

## Boundaries

- Each connector has a typed configuration and runs only after a user adds it.
- Notes and Mail use user-triggered macOS Automation; there is no background or broad account scan.
- Folders and Git repositories are picked locally through an open panel.
- Records and normalized documents persist under Application Support, are content-free in logs, and can be deleted per source.
- The chat responder performs deterministic local keyword retrieval and names its source evidence.

## Implementation tasks

- [x] Add connector domain types, local persistence, and search.
- [x] Add Notes, Mail, recursive Folder, and Git connector implementations.
- [x] Add a coordinator for sync, pause/resume, reauthorization, health, and complete deletion.
- [x] Expose the connector library through a SwiftUI source manager and composer add-source control.
- [x] Route chat responses through local indexed evidence.
- [x] Add focused tests for denial, malformed content, duplicates, permission changes, deletion, and Git metadata.
- [ ] Build, run focused tests, and package the app.
