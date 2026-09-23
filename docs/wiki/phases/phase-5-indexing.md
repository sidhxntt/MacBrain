# Phase 5: connectors and incremental indexing

## Problem

NotchBrain needs rich local sources without treating the user’s whole disk or every application database as an implicit corpus.

## Treatment

Connectors normalize their records into stable source identity, content, metadata, and open-location provenance. Folder and Git sources reconcile changed/removed items; Apple and browser integrations retain per-source lifecycle and health. Index jobs are durable; only a verified committed state becomes search eligible.

## Verification and boundary

Connector lifecycle, adversarial fixtures, browser catalog, source index, scheduler, and fresh-install tests support the contract. Storage-format drift, large real libraries, and all permission combinations require live acceptance.
