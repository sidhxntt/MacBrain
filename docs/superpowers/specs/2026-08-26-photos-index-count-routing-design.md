# Photos Index Count Routing Design

## Goal

Answer first-person Photos count questions from the verified local Photos index, without attempting evidence retrieval or exposing unrelated local material.

## Root cause

`LocalQueryPlanner` recognizes a count only after `SourceVocabulary` resolves a connector scope. The prompt “How many photos do I have indexed?” contains neither the existing phrase `my photos` nor `photos metadata`, so it becomes an unscoped evidence search. If retrieval falls back, unrelated files can be rendered as local evidence.

## Design

`SourceVocabulary` will add a narrowly scoped count resolver. It activates only when a prompt has both a count phrase and first-person ownership language, then maps a connector noun such as `photos` to its connector kind. `LocalQueryPlanner` will use this resolver only when ordinary source vocabulary did not identify a scope.

The resulting `.connector(.count, scope: [.photos])` plan continues through the existing `ConnectorQueryService` and `LocalSourceRepository`. That path uses only a verified, authorized SQLite index; during a refresh it returns the last committed Photos count. It does not retrieve documents, invoke the model, create citations, or render source content.

## Verification

Tests must prove the screenshot prompt resolves to the Photos count plan, a verified Photos fixture returns its exact count without provider access, and an in-progress Photos refresh returns the last verified count. A public Photos-framework count question must not be mistaken for local source access.
