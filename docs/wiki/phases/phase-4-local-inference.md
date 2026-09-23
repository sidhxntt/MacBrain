# Phase 4: local inference

## Problem

A local-first app needs model discovery, setup, streamed answers, cancellation, and useful recovery behavior without silently sending personal data to a hosted fallback.

## Treatment

`InferenceProvider` abstracts the provider surface and `OllamaClient` implements the local HTTP protocol. Setup distinguishes missing runtime, unavailable server, missing models, and invalid model-role selection. The responder bounds prompts, streams partial output, supports cancellation, and preserves evidence search when inference is unavailable.

## Verification and boundary

Mocked protocol, stream, timeout/retry, setup, and live-integration tests cover controllable behavior. Actual Ollama/model installation, memory pressure, and model quality are real-machine acceptance requirements.
