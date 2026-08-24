# Phase 04 — Ollama and Local Model Setup

## Goal

Provide a provider-neutral inference layer and a guided Ollama setup with lightweight defaults.

## Deliverables

- Provider protocol for health, models, embeddings, streaming, cancellation, and status.
- Ollama local HTTP client.
- Missing-runtime/model setup flow.
- Lightweight default chat and embedding models.
- Memory and failure diagnostics.

## Implementation sequence

- [ ] Define `InferenceProvider` and typed status/error/model types.
- [ ] Detect missing Ollama, unavailable server, missing models, incompatible models, and failed requests.
- [ ] Add setup screens: explain local processing, show disk/RAM estimates, download models, and test connection.
- [ ] Default to a quantized 3B–4B chat model and lightweight embedding model; allow model changes later.
- [ ] Parse streaming generation responses and publish partial tokens.
- [ ] Implement cancellation, timeout, retry policy, and connection recovery.
- [ ] Add a mock HTTP server with recorded responses for deterministic tests.
- [ ] Manually test against Ollama on the target Apple-silicon Mac.

## Exit criteria

A new user can detect/install Ollama, download both models, test them, stream a response, cancel generation, and receive actionable errors without cloud inference.
