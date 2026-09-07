# Development and Verification

## Build and test

MacBrain is a Swift Package targeting macOS 14+. Use `swift test` for the complete local suite. Tests cover panel geometry/activation, stores, SQLite/migrations, chunking, indexing jobs, source lifecycle/health/query scope, browser profiles, retrieval fusion/evidence policy/citations, Ollama client/streaming/setup, memories/context safeguards, live Mac routing, graph extraction, and stress/real-backend acceptance paths.

## Verification strategy

Pure logic is isolated behind protocols so deterministic tests can use temporary databases, fixture repositories/documents, controlled clocks/screens/filesystems, and mock inference. Connector adversarial and fresh-install tests verify the privacy-critical rule that selection/permission/complete commit happen before retrieval. Prompt-barrage and real-backend suites test grounded-response behavior. Manual acceptance remains required for clean-machine Ollama installation, actual TCC prompts, multi-monitor panels, cancellation during real streams, and performance on supported Apple silicon.

## Documentation publishing

`docs/wiki/` is the reviewed source of truth. Run `node scripts/render-github-wiki.mjs ../notchbrain.wiki` against a clone of `https://github.com/sidhxntt/NotchBrain.wiki.git`, inspect the generated pages, commit that separate Wiki repository, and push it. The renderer writes only MacBrain-managed pages and never deletes unrelated Wiki content.

When a capability changes, update its user behavior, state owner, source/permission boundary, failure/recovery behavior, status (implemented versus planned), and test evidence in the same change.
