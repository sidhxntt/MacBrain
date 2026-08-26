# Connector Capability Status Responses

**Date:** 2026-08-26

## Problem

The question “Can you read my notes from Apple Notes?” is classified as an explicit local-content request. `StreamingChatResponder` therefore attempts retrieval and, when no indexed note matches the wording, returns “I couldn't find matching material.” That is misleading: the user asked whether the connector is available, not for note content.

## Decision

Add a small, deterministic connector-capability response before file reading, model availability, and retrieval. It applies only when the prompt is a direct ability/access question and `SourceQueryScope` identifies one or more connector kinds.

Examples of recognized forms include “Can you read my Apple Notes?”, “Do you have access to my Mail?”, and “Are my reminders available?” A request that includes a content operation or target, such as “Search my Apple Notes for Aurora” or “Can you read my notes and summarize Aurora?”, remains on the existing retrieval path.

## Response contract

For each named connector:

- no record: explain that it is not connected and that MacBrain can use it after the user connects and authorizes it;
- `ready` or `syncing`: confirm that it is connected locally and can be searched, noting when synchronization is in progress;
- `needsAuthorization`: state that it is connected but macOS permission is required, without exposing retained content;
- `paused`: state that synchronization is paused; already indexed material remains searchable, but new changes require resuming sync;
- `failed`: state that the last sync failed; already indexed material may remain searchable, and direct the user to Sources for retry.

The response contains no retrieved evidence, citation cards, model tokens, embedding calls, or source content. Multiple explicitly named connectors receive a concise per-connector status summary.

## Design alternatives considered

1. Reword the existing empty-retrieval message. This would still misrepresent a capability question and would make real missing-content queries less useful.
2. Ask the local model to infer connector availability. This adds latency and allows hallucinated status.
3. **Chosen:** derive a deterministic response from the repository's connector records before retrieval. It is accurate, private, fast, and keeps content retrieval unchanged.

## Data flow

`prompt` → direct-capability recognizer → `SourceQueryScope` → `LocalSourceRepository.allRecords()` → rendered connector-state response → terminal stream.

All other prompts continue through the existing router, optional file reader, model-status check, retrieval, and citation pipeline.

## Tests

Add real responder tests for Apple Notes in the disconnected, ready, authorization-needed, paused, and failed states. Each test verifies the expected status text, no citation section, no provider embedding call, and no model-generation call. Add a negative test proving a content request containing a capability verb still reaches normal grounded retrieval.

## Scope

This changes chat behavior only. It does not alter connector synchronization, Source Manager UI, authorization handling, retrieval eligibility, or citation rendering.
