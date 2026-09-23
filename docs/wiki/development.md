# Development and verification

## Build and test

NotchBrain is a Swift Package targeting macOS 14+. Run:

```bash
swift test
```

The suite covers panel geometry/activation, stores, migrations and SQLite transactions, chunking/indexing, connector lifecycle/health/query scope, browser profiles, hybrid evidence/citations, Ollama client/provider/setup, streaming, memory/context safeguards, live-Mac routing, graph extraction, and stress/real-backend acceptance paths.

## Evidence hierarchy

1. **Unit/integration tests** use temporary databases, fixtures, controlled clocks/screens, and mock inference for deterministic contracts.
2. **Stress and acceptance corpus** exercises adversarial connectors and grounded-answer behavior. See `Tests/StressTests/`.
3. **Manual macOS acceptance** is required for clean-machine setup, TCC prompts, real Ollama/model setup, multi-monitor/Spaces behavior, real streaming cancellation, opening sources, and target-hardware performance.

A passing test suite is strong evidence for the code paths it executes; it is not proof that every external macOS/runtime condition is satisfied.

## Documentation and Wiki publishing

`docs/wiki/` is the reviewed source of truth. Run:

```bash
node scripts/render-github-wiki.mjs ../notchbrain.wiki
```

against a clone of `https://github.com/sidhxntt/NotchBrain.wiki.git`. Inspect the generated Wiki diff, commit that separate Wiki repository, and push it. The renderer writes only managed NotchBrain pages and does not delete hand-maintained content.

When behavior changes, update its product behavior, state owner, consent/failure boundary, implementation-guide evidence, and delivery label in the same change.
