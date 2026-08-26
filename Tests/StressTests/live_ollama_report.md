# Live Ollama soak report

Date: 2026-08-26  
Chat model: `qwen3:8b`  
Embedding model: `nomic-embed-text`

## Result

- Ollama health, model discovery, embedding generation, visible chat streaming, and injected Mac-context checks passed.
- 16/16 production prompts completed; 0 timed out, failed, hung, or remained pending.
- Source-markup and raw-evidence contamination checks: 0 failures.
- Bounded generation concurrency: 2.
- A synthetic connected-source query returned its known owner/date with a valid `[S1]` card and no evidence fallback in 0.685 s.
- Time to first token: 0.446 s average, 0.102 s median, 2.864 s maximum.
- Total prompt latency: 1.245 s average, 0.825 s median, 3.893 s maximum.
- Entire live integration suite: 4 tests passed in 15.085 s.

## Per-case latency

| Label | Route | First token | Total |
|---|---|---:|---:|
| casual | casual | 0.102 s | 0.844 s |
| coding | general | 0.325 s | 0.805 s |
| explicit-empty | explicitLocal | 0.005 s | 0.005 s |
| filesystem | general | 1.412 s | 3.893 s |
| implicit-empty | implicitLocal | 0.101 s | 1.035 s |
| live-memory | liveMac | <0.001 s | <0.001 s |
| logic | general | 2.864 s | 3.444 s |
| macos-howto | general | 0.100 s | 1.320 s |
| math | general | 0.100 s | 0.185 s |
| privacy | restricted | <0.001 s | <0.001 s |
| public-source-term | general | 0.100 s | 2.770 s |
| science | general | 0.936 s | 1.761 s |
| summary | general | 0.101 s | 0.515 s |
| translation | general | 0.106 s | 0.233 s |
| unicode | general | 0.608 s | 2.334 s |
| writing | general | 0.278 s | 0.777 s |

The report records stable case labels and routes rather than private prompt or source text. Model-quality assertions are intentionally separate from routing/runtime assertions; this run verified non-empty bounded output and terminal behavior, not frontier-model factual equivalence.
