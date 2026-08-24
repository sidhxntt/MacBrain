# Phase 10 — Privacy, Testing, Packaging, and Release

## Goal

Turn the working MVP into a safe, recoverable, signed native macOS release.

## Implementation sequence

- [ ] Audit every filesystem access against selected folders and security-scoped bookmarks.
- [ ] Ensure no document content, prompts, logs, or embeddings leave the machine.
- [ ] Store future provider settings/tokens in Keychain and redact sensitive values from logs.
- [ ] Add privacy controls for indexed locations, exclusions, memories, deletion, export, and model storage.
- [ ] Validate sandbox entitlements, Accessibility explanations, local Ollama connection behavior, signing, and notarization prerequisites.
- [ ] Add performance tests for launch, panel-open latency, indexing throughput, search latency, time-to-first-token, and memory pressure.
- [ ] Run failure tests for corrupt files, deleted sources, unavailable Ollama, missing models, database migration failure, and interrupted jobs.
- [ ] Run a clean-machine acceptance test from install through complete data removal.
- [ ] Document hardware requirements, model sizes, privacy behavior, recovery steps, and known limitations.

## Release gates

- [ ] No unsupported answer claim appears as certain.
- [ ] Every citation opens or identifies its original source.
- [ ] No silent broad filesystem indexing occurs.
- [ ] User deletion removes indexed data and memories as promised.
- [ ] The app works without a hosted AI API.
- [ ] Ollama/model failures are recoverable and actionable.
- [ ] The app behaves correctly on multiple displays.
- [ ] The clean-machine acceptance flow passes.

## Exit criteria

The MVP can be distributed to a small beta group with documented setup, predictable local storage, privacy controls, crash/error recovery, and a reproducible release build.
