# Roadmap and delivery status

## Foundations present in the repository

The codebase contains the native sidebar and activation policy, SQLite/migrations, source records and connector lifecycle, deterministic chunking, lexical-first/hybrid retrieval, evidence acceptance/citation validation, local chat/memory records, Ollama integration, local system routing, and connector/real-backend stress coverage. These are implemented foundations with focused tests, not a claim that every source or machine-dependent behavior has shipped as a polished release.

## MVP hardening work

- Perform clean-machine onboarding, real Ollama/model setup, stream cancellation, and recovery acceptance.
- Exercise source selection, denial, revocation, pause/resume, deletion, and reauthorization on real macOS permissions.
- Run representative source corpora for indexing time, query latency, memory pressure, citation usefulness, and connector failure recovery.
- Verify multi-display/Spaces/focus behavior and package/sign/notarize the release path.
- Keep the acceptance corpus current as connector and retrieval behavior changes.

## Planned, not implemented promises

- Bundled MLX/MLX-LM or `llama.cpp` inference.
- Lower-latency filesystem observation beyond the current refresh model.
- Broader, maintained source integrations as each permission and storage format is validated.
- OCR/screenshots, richer editor/browser live context, email/calendar/reminder write actions, and coding-agent workflows.
- Any action that mutates another system, always behind a reviewable confirmation boundary.

The ordering is deliberate: reliable consent, committed local retrieval, source provenance, and graceful inference failure come before greater automation or data reach.
