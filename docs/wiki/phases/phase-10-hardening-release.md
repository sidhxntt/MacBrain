# Phase 10: hardening and release

## Problem

A green unit suite does not prove the native app is safe and usable on a clean Mac with real permissions, displays, local models, and personal source sizes.

## Treatment

The project keeps manual acceptance separate from deterministic tests: clean-install onboarding, Ollama setup and streaming cancellation, TCC denial/recovery, multi-monitor behavior, source deletion, citation opening, and stress/real-backend prompts are all explicit release work. Documentation labels those boundaries rather than promoting plans into guarantees.

## Verification and boundary

Use `swift test` for the local regression suite, then perform the scenario-based acceptance in `Tests/StressTests/` and the MVP documents. Packaging, signing, notarization, and broad hardware/performance qualification remain release-engineering work outside a unit-test result.
