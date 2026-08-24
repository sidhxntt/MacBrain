# Phase 07 — Lightweight Knowledge Graph

## Goal

Add graph-aware retrieval for people, projects, repositories, decisions, and topics without introducing a separate graph database.

## Initial graph model

Entity types: person, project, repository, document, decision, organization, topic, date.

Relationship types: `mentions`, `belongs_to_project`, `works_on`, `made_decision`, `supported_by`, `related_to`, `supersedes`.

## Implementation sequence

- [ ] Implement graph CRUD through SQLite tables with provenance and confidence on every fact.
- [ ] Extract obvious candidates using deterministic patterns for paths, repository names, headings, dates, and repeated names.
- [ ] Use the local chat model for harder entity/relation extraction only in background jobs.
- [ ] Normalize aliases without merging low-confidence entities automatically.
- [ ] Remove mentions and relationships when their source chunks are deleted or replaced.
- [ ] Add bounded entity expansion to retrieval with depth and result limits.
- [ ] Label graph-derived evidence separately from direct source excerpts.
- [ ] Test aliases, conflicting relations, superseding decisions, provenance, cleanup, and graph-unavailable fallback.

## Exit criteria

Graph data improves relationship and multi-document questions, remains inspectable and source-backed, and never prevents normal keyword/vector search from working.
