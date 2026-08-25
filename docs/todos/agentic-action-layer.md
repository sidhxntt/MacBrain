# Agentic macOS action layer

## Decision

MacBrain should become a local agentic layer for a user's Mac: it can understand a request, inspect permitted local context, propose a concrete action, and carry it out only within the user's approved scope. Examples include opening an app or file, revealing a source in Finder, creating a Calendar event, drafting an email, or running a narrowly-defined Git workflow.

This is **post-MVP Phase 6 — Controlled Action Layer** in the [post-MVP roadmap](../superpowers/plans/2026-08-23-notch-brain-post-mvp.md). It is not the MVP's Phase 06, which remains retrieval and citations.

## Why Phase 6

Agentic actions must come after MacBrain can reliably retrieve grounded evidence, cite it, maintain explicit permissions, and recover safely from failures. An agent that acts before its context is dependable is unsafe and difficult to trust.

Required preceding work:

1. MVP Phases 06–10: cited retrieval, knowledge graph, durable conversations/memories, live-context safeguards, and release hardening.
2. Post-MVP Phases 0–5: beta validation, better retrieval, bundled inference, polished workflows, and rich current-context integrations.
3. A per-action permission, confirmation, audit, cancellation, and rollback foundation.

## Action model

Each action is typed, local, observable, and independently permissioned.

| Class | Examples | Default execution |
|---|---|---|
| Read-only | Open application, open/reveal file, inspect current system status, copy citation | Immediate after user request when permission exists |
| Reversible write | Create draft email, create reminder, create Calendar event, edit a selected text file | Reviewable preview and explicit confirmation; provide undo where platform supports it |
| High-impact write | Send email/message, delete/move files, execute Git push, install software, change system settings | Exact preview, strong confirmation, scoped authorization, audit record; never automatic |
| Multi-step workflow | Prepare meeting brief, update project files then create commit, collect source material then create reminder | Plan shown first; user approves each mutating step or pre-approves an explicit bounded plan |

## Architecture

- `ActionProtocol`: typed input/output schema, permissions, side-effect class, reversibility, and timeout.
- `ActionRegistry`: only registered, reviewed action adapters are available to model/tool selection.
- `ActionPlanner`: turns an intent into a visible, bounded action plan. Model output is never executable code by itself.
- `ConfirmationCard`: shows app/file/account target, exact mutation, preview/diff, and cancel/approve controls.
- `ActionExecutor`: performs one approved action at a time, carries cancellation, duplicate prevention, and result validation.
- `ActionAuditStore`: local SQLite record of plan, approval, execution result, timestamps, provenance, and undo reference. Never store secret payloads in logs.
- App adapters: use supported macOS mechanisms only—App Intents, Shortcuts, Automation/Apple Events, documented local APIs, Finder URLs, and security-scoped file access.

## Safety rules

- No action exists merely because an LLM suggests it.
- No command shell, arbitrary AppleScript, or arbitrary app-memory automation generated from chat text.
- Never bypass TCC, Full Disk Access, sandboxing, application permissions, or account authorization.
- Scope permission to the exact app, account, repository, file, or folder where possible.
- Revalidate target and preview immediately before execution; reject stale plans.
- Stop on permission denial, ambiguous target, cancellation, partial failure, or changed source state.
- Destructive and external side effects always require confirmation. No silent background writes.
- User can inspect, revoke, pause, delete, and export local action history.

## Delivery sequence

1. **Read-only actions:** open source, reveal in Finder, copy citation, open selected app/file, inspect live system information.
2. **Draft actions:** create but do not send email/message drafts; create previewed notes, reminders, and Calendar events.
3. **Scoped file and Git actions:** present exact diffs, write only inside user-selected roots, require confirmation for every mutation.
4. **Bounded workflows:** let users approve a displayed multi-step plan with step-level stop and recovery.
5. **Custom action integrations:** only through declared, consented app capabilities described in [Future custom app integrations](./future-custom-integrations.md).

## Acceptance criteria

- Every action has a typed schema, visible target, permission disclosure, and test fixture.
- Every mutation has confirmation, cancellation, duplicate-execution protection, and local audit history.
- Tests cover permission denial, unavailable app, ambiguous targets, malformed tool output, stale preview, cancellation, timeout, partial completion, and undo/compensation where supported.
- A model failure cannot trigger an unreviewed action or corrupt local sources, chats, or connector data.

## Non-goals

- Replacing macOS security controls or becoming unrestricted remote-control software.
- Hidden autonomous action loops.
- Sending user content to hosted services by default.
- Giving the model arbitrary Terminal access.
