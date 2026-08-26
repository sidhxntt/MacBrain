# Live Ollama Connector and Soak Report

Status: Current-tree pass. The live fixtures use the same verified SQLite generation boundary as production retrieval.

Date: 2026-08-26  
Chat model: `qwen3:8b`  
Embedding model: `nomic-embed-text`

## Result

- Full suite: 5 tests passed, 0 failures, in 76.094 seconds.
- Connector answer-quality matrix: 66/66 cases passed (`11 connectors × 6 dimensions`).
- Production soak: 16/16 prompts completed.
- Health, model discovery, embedding generation, visible streaming, injected Mac context, and synthetic folder grounding passed.
- Bounded connector generation concurrency: 2; per-case deadline: 60 seconds.
- Every live connector case reached `.completed`. No case timed out, hung, leaked a forbidden marker, used the wrong connector type, or emitted an invalid citation.
- Answer paths were reported separately: 47 model-authored answers, 8 verified-evidence fallbacks after the model omitted a required field or valid citation, and 11 deterministic permission-state answers. All 66 final user-visible answers satisfied their fact, freshness, citation, permission, and isolation assertions.

Command:

```sh
env MACBRAIN_LIVE_OLLAMA=1 \
  CLANG_MODULE_CACHE_PATH=/private/tmp/macbrain-live-clang-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/macbrain-live-swiftpm-cache \
  swift test --filter OllamaLiveIntegrationTests
```

The test logs one `LIVE_CONNECTOR_AUDIT` record per matrix cell and one `LIVE_SOAK` record per production prompt, including stable case ID, route, answer path, first-token latency, total latency, and terminal state. It deliberately does not log private prompt or connector content.

## What the live matrix checks

For each connector, the final response must reproduce every requested controlled fact, retain the expected connector type and known citation, prefer the current marker, refuse inaccessible evidence, and exclude a same-token decoy in another connector. Model-authored output is accepted only with known citations and all required facts; otherwise MacBrain intentionally renders bounded evidence from the verified retrieval result and records that path separately.

The first current-tree attempt failed immediately because this live harness still used the legacy `replaceDocuments` seeding path. The hardened retriever correctly rejected those unverified rows. The harness now commits ready records and documents together with `commitSourceGeneration`, matching the production searchable-state invariant; a targeted Notes case passed before the complete rerun.
