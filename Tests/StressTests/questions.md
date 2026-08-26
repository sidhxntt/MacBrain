# Overview

This card tests the shipped MVP using only the deterministic corpus in
[`test/`](/Users/sidhxntt/Desktop/Code/Products/NotchBrain/test). It is designed
for manual testing in the running app after the **test** folder reports
**Ready · 5 items**.

## Before starting

1. In **Sources**, sync `/Users/sidhxntt/Desktop/Code/Products/NotchBrain/test`.
2. Confirm it contains these five files: `.env`, `notes.md`, `nested/plan.txt`,
   `temp_1.txt`, and `temp_2.md`.
3. Use a new chat for Q01, then keep the same chat for follow-up Q07.
4. For every cited answer, use **Open source**. A card fails if it opens an
   unrelated file, has no readable title, or cannot identify its source.

## How to score a response

- **Pass:** every required fact appears, no prohibited fact appears, and every
  factual claim has a citation to the named file.
- **Fail:** a required fact is missing, an answer invents a fact, a citation is
  missing/wrong/unopenable, or an unrelated connected source is used instead of
  the `test` corpus.
- Wording may differ; factual content and source provenance may not.

## Fixture reference

| File | Canonical facts |
| --- | --- |
| `notes.md` | Decision `AUR-LOCAL-042`; Riya Sen owns the beta decision; date `2026-09-15`; local retrieval; SQLite FTS5; citations are required. |
| `nested/plan.txt` | Plan `AURORA-R1`; recursive indexing; direct evidence comes before graph expansion; Riya Sen is rollback owner; missing/unopenable citation blocks release. |
| `temp_1.txt` | SQLite FTS5; `nomic-embed-text`; `qwen3:8b`; no hosted AI API for document content. |
| `temp_2.md` | QA handoff; exact expected combined summary; the corpus names no CEO. |
| `.env` | `DATABASE_URL=local-fixture-only`; `AURORA_TEST_REGION=ap-south-1`; fake fixture secret. |

## Question cards

| ID | Phase coverage | Topics and features tested | Ask / action | Anticipated answer or result |
| --- | --- | --- | --- | --- |
| Q01 | 5, 6 | Folder indexing; FTS/vector retrieval; citations | `What is Aurora's approved search foundation?` | **SQLite FTS5**, cited to `notes.md` and/or `temp_1.txt`. |
| Q02 | 5, 6 | Fact retrieval; source provenance; citation accuracy | `Who owns Aurora's beta release decision and what is the target date?` | **Riya Sen** and **2026-09-15**, cited to `notes.md`. |
| Q03 | 5, 6 | Recursive nested-file indexing; exact retrieval | `What is the rollback plan ID and who owns rollback?` | **AURORA-R1** and **Riya Sen**, cited to `nested/plan.txt`. |
| Q04 | 5, 6 | Retrieval ordering; direct-evidence priority | `What must happen before graph-expanded evidence is used?` | **Direct evidence must be retrieved first**, cited to `nested/plan.txt`. |
| Q05 | 5, 6 | Local-model metadata retrieval; citations | `Which local models are configured for Aurora's embeddings and chat?` | **nomic-embed-text** for embeddings and **qwen3:8b** for chat, cited to `temp_1.txt`. |
| Q06 | 5, 6 | Hidden-file indexing; exact-value retrieval; citation fidelity | `What is the Aurora test region?` | **ap-south-1**, cited to `.env`. This proves hidden-file indexing and citation fidelity. |
| Q07 | 6, 8 | Follow-up context; source-card continuity | After Q02, ask: `Which file established the beta date?` | **notes.md**, with a valid source card for `notes.md`. |
| Q08 | 6 | Grounding; uncertainty; hallucination refusal | `Who is Aurora's CEO?` | States that the **local evidence does not establish a CEO**. It must not invent a name. |
| Q09 | 6, 7 | Multi-document reasoning; graph-aware expansion; citation coverage | `Give the complete Aurora beta handoff: decision owner, rollback owner, target date, and search foundation.` | **Riya Sen** owns both decision and rollback; date **2026-09-15**; foundation **SQLite FTS5**. Citations must include both `notes.md` and `nested/plan.txt` (and may include `temp_1.txt`). |
| Q10 | 6, 7 | Relationship retrieval; release-policy grounding | `Why would an Aurora release be blocked?` | A **missing or unopenable citation** is a release blocker, cited to `nested/plan.txt`. |
| Q11 | 8 | Streaming generation; cancellation; retry | Start Q01, click **Stop** during streaming, then retry Q01. | The first response preserves useful partial text; retry produces a fully cited SQLite FTS5 answer. |
| Q12 | 8 | Explicit memory CRUD; persistence; deletion | Explicitly save the memory: `Aurora test preference is local-only.` Edit it to `Aurora test preference is local-only and cited.` Then forget it. | Memory appears only after explicit save, persists after edit/relaunch, and disappears after **Forget**. |
| Q13 | 9 | Opt-in clipboard context; visible chips; one-turn expiration | Copy `Aurora one-turn context 987`, choose **Add live context → Clipboard**, then ask `Repeat my clipboard context exactly.` | A visible chip and answer contain exactly **Aurora one-turn context 987**. Send the same question again without adding context: it must no longer claim to know the phrase. |
| Q14 | 9 | Repository-context relevance; prompt-context safeguards | Add repository context, then ask Q01. | Aurora answer remains grounded in Aurora files; repository/branch data is not presented as evidence for the search foundation. |
| Q15 | 10 | Source deletion; privacy; indexed-data removal | Remove the `test` source, confirm deletion, then repeat Q01 and Q06. | The app no longer presents Aurora facts or `.env` values as indexed evidence. Reconnect and sync the folder to restore this card. |

## Incremental-sync card

1. Create `test/temp_3.md` containing exactly: `Aurora sync marker: fifth-plus-one.`
2. Choose **Sync now** from the **test** source menu.
3. Ask: `What is the Aurora sync marker?`

**Anticipated answer:** `fifth-plus-one`, cited to `temp_3.md`.

Then delete `temp_3.md`, choose **Sync now**, and repeat the question.

**Anticipated result:** MacBrain says the local evidence does not establish a
sync marker; it must not cite the deleted file.

## Release gate

The corpus passes when Q01–Q10 all return the anticipated facts with exact,
openable citations; Q08 refuses to invent a CEO; Q11–Q14 exhibit the stated
chat/memory/context behavior; and the incremental-sync card both adds and
prunes `temp_3.md` correctly.
