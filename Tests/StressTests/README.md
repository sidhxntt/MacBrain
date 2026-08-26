# Stress-Test Index

Use controlled test records only. Connect, authorize, and sync a connector
before running its card. Mark any unavailable connector **not tested**, never
passed.

## Overview cards

- [Overview](questions.md) — deterministic folder-fixture acceptance questions.
- [Stress Overview](stress_test_questions.md) — cross-connector black-box stress card.
- [Acceptance card](acceptance_tests.md) — full app acceptance scenarios.
- [Production prompt corpus](production_prompt_corpus.md) — 300+ deterministic routing and terminal-state cases.
- [Live Ollama report](live_ollama_report.md) — latest opt-in local-model soak results.
- [Production chat acceptance audit](production_chat_acceptance_audit.md) — criterion-by-criterion deterministic, live, sanitizer, and runtime evidence.

## Connector cards

- [Folder](connectors/folder.md)
- [Apple Mail](connectors/apple_mail.md)
- [Apple Calendar](connectors/apple_calendar.md)
- [Apple Reminders](connectors/apple_reminders.md)
- [Apple Notes](connectors/apple_notes.md)
- [Apple Contacts](connectors/apple_contacts.md)
- [Browser Profiles](connectors/browser_profiles.md)
- [Messages](connectors/messages.md)
- [Photos](connectors/photos.md)
- [Apple Books](connectors/apple_books.md)
- [Git Repository](connectors/git_repository.md)

## Cross-cutting use-case cards

- [Evidence and citations](use_cases/evidence_and_citations.md)
- [Cross-source reasoning](use_cases/cross_source_reasoning.md)
- [Freshness and deletion](use_cases/freshness_and_deletion.md)
- [Privacy and authorization](use_cases/privacy_and_authorization.md)
- [Conversation and live context](use_cases/conversation_and_live_context.md)
- [Model failure and recovery](use_cases/model_failure_and_recovery.md)
