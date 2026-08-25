# Phase 04 — Ollama and Local Model Setup

## Goal

Provide a provider-neutral inference layer and a guided Ollama setup with lightweight defaults.

## Deliverables

- [x] Provider protocol for health, models, embeddings, streaming, cancellation, and status.
- [x] Ollama local HTTP client.
- [x] Missing-runtime/model setup flow.
- [x] Lightweight default chat and embedding models.
- [x] Memory and failure diagnostics.

## Implementation sequence

- [x] Define `InferenceProvider` and typed status/error/model types.
- [x] Detect missing Ollama, unavailable server, missing models, incompatible models, and failed requests.
- [x] Add setup screens: explain local processing, show disk/RAM estimates, download models, and test connection.
- [x] Default to Qwen3 8B for chat and Nomic Embed Text for embeddings; allow model changes later.
- [x] Parse streaming generation responses and publish partial tokens.
- [x] Implement cancellation, 30-second timeout, two transient-connection retries, and connection recovery.
- [x] Add deterministic mocked local HTTP responses for model, embedding, error, retry, and stream tests.
- [ ] Manually test against Ollama on the target Apple-silicon Mac.

## Runtime behavior

MacBrain calls only the local Ollama API at `http://127.0.0.1:11434`; it has no hosted inference fallback. If Ollama is absent, stopped, or missing a selected model, chat remains usable with the existing local evidence response while Settings explains the recovery step. Installed model choices persist locally in macOS preferences. Chat and embedding selections are role-aware: chat models cannot be selected as embedding models, and invalid older preferences are corrected to a discovered embedding model.

When Ollama is ready, chat responses stream into the conversation as partial tokens. **Stop** cancels the local generation and keeps the useful partial answer. A transient localhost connection failure retries twice; non-transient failures remain visible as actionable diagnostics. MacBrain requests a 30-minute local model keep-alive, disables hidden reasoning output, uses a focused low-temperature profile, and batches durable chat writes during token streaming to keep responses responsive.

Every chat receives a bounded, local system profile: current account display name, Mac name/model, processor, memory, macOS version, disk capacity, locale, and time zone. This profile lets MacBrain answer questions about the user’s Mac without connecting a source. It excludes serial numbers, credentials, personal files, contacts, messages, app content, and network identifiers.

## Manual Apple-silicon acceptance

1. Install and open Ollama for Mac.
2. In MacBrain Settings, choose **Check local setup**.
3. Download `qwen3:8b` and `nomic-embed-text` from the Local AI section.
4. Ask a question; verify partial tokens appear, then test **Stop** during generation.
5. Ask who is using the Mac and what processor it has; verify the answer comes from the local system profile.
6. Quit and reopen MacBrain; verify selected model choices persist and no cloud account or API key is requested.

## Exit criteria

A new user can detect/install Ollama, download both models, test them, stream a response, cancel generation, and receive actionable errors without cloud inference. The final manual acceptance requires a locally installed Ollama runtime and models.
