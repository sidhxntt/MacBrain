# MacBrain Full-App Acceptance Card

This is the end-to-end companion to [`questions.md`](questions.md). It checks
the shipped app across phases 1–9. Phase 10 release/hardening work is excluded
for now.

## Test environment

- Run the current local build of MacBrain.
- Ollama must expose `qwen3:8b` and `nomic-embed-text`.
- Connect and sync [`test/`](test/) until it reports **Ready · 5 items**.
- Use a fresh chat unless a card says to continue the existing conversation.

## Scoring

- **Pass:** the anticipated result happens and the prohibited result does not.
- **Fail:** a required result is missing, stale/private information appears, or
  the app becomes unavailable.
- Record the card ID, observed result, and source card/file path for each fail.

## Acceptance cards

| ID | Phase | Feature | Setup / action | Anticipated result | Must not happen |
| --- | --- | --- | --- | --- | --- |
| A01 | 1 | App shell | Launch MacBrain. Open and close the main workspace twice. | A single usable workspace appears each time. | Duplicate windows, a blank workspace, or a crash. |
| A02 | 2 | Activation | Use the configured activation gesture/handle. Drag it, then activate it. | Dragging repositions it; activation opens MacBrain. | A drag accidentally activates the app. |
| A03 | 2 | Permission denial | Decline a connector permission when prompted, then open Sources. | The connector clearly reports a permission problem and remains recoverable. | Content is indexed despite denial or the app stalls. |
| A04 | 3 | Local persistence | Create a chat named `Acceptance persistence`, quit MacBrain, relaunch. | The chat and its messages return. | Chat data is lost or duplicated. |
| A05 | 3 | Storage data | Ask `How much local storage is available?` twice, several seconds apart. | Each answer reflects a live local-system query. | The answer is served as a stale cached response. |
| A06 | 4 | Ollama readiness | Open model/settings status with Ollama running. | `qwen3:8b` and `nomic-embed-text` are available/ready. | A ready local service is shown as unavailable. |
| A07 | 4 | Ollama recovery | Stop Ollama, send a non-source question, then start Ollama and retry. | Failure is understandable and retry succeeds after recovery. | The UI hangs indefinitely or loses the prompt. |
| A08 | 5 | Folder indexing | Connect `test/`, sync, and verify the source count. | Exactly five supported fixture files are indexed, including `nested/plan.txt` and `.env`. | `node_modules/ignored.txt` is indexed. |
| A09 | 5 | Incremental add | Add `temp_3.md` containing `Aurora sync marker: fifth-plus-one.`, choose **Sync now**, then ask for the marker. | `fifth-plus-one` is retrieved and cited to `temp_3.md`. | A manual reconnect is required. |
| A10 | 5 | Incremental update | Change that marker to `second-marker`, choose **Sync now**, and ask again. | Only `second-marker` is returned. | The old marker is returned as current. |
| A11 | 5 | Incremental prune | Delete `temp_3.md`, choose **Sync now**, and ask for the marker. | The app says local evidence does not establish a marker. | It cites or returns the deleted marker. |
| A12 | 5 | Hidden files | Ask `What is the Aurora test region?` | `ap-south-1`, cited to `.env`. | The fake secret is exposed when it was not requested. |
| A13 | 6 | Grounded retrieval | Ask Q01–Q06 from `questions.md`. | Every anticipated fact is present with an openable local citation. | Unsupported facts or an unrelated connected source are used. |
| A14 | 6 | Negative grounding | Ask `Who is Aurora's CEO?` | The answer says local evidence does not establish a CEO. | A CEO name is invented. |
| A15 | 6 | Source opening | For every source card from A13–A14, select **Open source**. | The cited local fixture file opens and has a readable title. | A different file opens, or the source cannot be identified. |
| A16 | 6 | Source-backed cancellation | Start Q01 and choose **Stop** while it is responding. | Visible verified evidence remains; retry yields the complete grounded result. | All useful response content disappears or a stale uncited answer appears. |
| A17 | 6 | Multi-document evidence | Ask Q09 from `questions.md`. | Decision owner, rollback owner, date, and FTS5 are present; citations cover `notes.md` and `nested/plan.txt`. | A partial answer is presented as complete. |
| A18 | 6 | Cache hit | In a fresh chat ask `Summarize Aurora's plan` twice without changing sources. | The second result is equivalent and returns without another model generation. | The answer changes without input/revision change. |
| A19 | 6 | Cache invalidation | Change a relevant Aurora fact, sync, and repeat A18. | The new fact appears; the old answer is not reused. | A stale cached answer appears. |
| A20 | 6 | Cache bypass | Repeat a live-system question and a direct file-content question. | Each is evaluated fresh, not reused from response cache. | A prior live/file answer is returned after its data changed. |
| A21 | 7 | Direct-evidence priority | Ask `What must happen before graph-expanded evidence is used?` | Direct evidence is stated first and cited to `nested/plan.txt`. | Graph-derived material replaces direct local evidence. |
| A22 | 7 | Graph-safe synthesis | Ask Q09, then inspect all citations. | The response remains attributable to local documents. | An inferred relationship is presented without supporting evidence. |
| A23 | 8 | Chat retry | Trigger a recoverable model failure, restore Ollama, and use **Retry**. | The same user prompt is retried once and completes. | A duplicate user message or unrelated prompt is sent. |
| A24 | 8 | Conversation context | Ask Q02, then ask `Which file established the beta date?` | `notes.md` is identified with its source card. | Context is lost or a new unsupported source is named. |
| A25 | 8 | Explicit memory | Save `Aurora test preference is local-only.`, edit it to add `and cited.`, quit/relaunch, then forget it. | It appears only after save, survives edit/relaunch, then disappears after Forget. | Memory is created implicitly or remains after Forget. |
| A26 | 9 | Clipboard opt-in | Copy `Aurora one-turn context 987`; choose **Add live context → Clipboard**; ask to repeat it exactly. | A visible Clipboard chip and answer contain the exact phrase. | Clipboard text is used without the opt-in action. |
| A27 | 9 | One-turn expiry | Immediately repeat the A26 question without another chip. | The app no longer claims it knows that phrase from clipboard. | The previous clipboard-derived answer is reused as context. |
| A28 | 9 | Repository relevance | Add repository context, then ask Q01. | The answer stays grounded in Aurora files; repository data is absent. | Branch/commit data is presented as Aurora evidence. |
| A29 | 9 | Context visibility | Add and remove each live-context type available in the composer. | Each selected context has a clear chip and removal control. | Hidden or irreversible context is attached. |

## Cleanup

1. Delete `test/temp_3.md` if created and choose **Sync now**.
2. Forget the A25 test memory.
3. Remove any temporary live-context chips.
4. Leave the `test` source connected for the next retrieval run.

## Exit criteria

The app passes this card when A01–A29 pass, no **Must not happen** condition
occurs, and every cited fixture source opens to the expected local file.
