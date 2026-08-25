# Explicit Local Connectors

## Outcome

MacBrain offers local read-only connectors for Apple productivity data, but creates and syncs them only after the user explicitly selects a connector and confirms the action. macOS remains the permission authority; a denied or unavailable source is visible in connector health and does not prevent other sources from working.

## Sources

- [x] Apple Notes and Mail through Automation.
- [x] Calendar and Reminders through EventKit.
- [x] Contacts through Contacts.
- [x] Safari bookmarks and Reading List through the local bookmarks library.
- [x] Messages through its local database, with Full Disk Access guidance.
- [x] Photos metadata through PhotoKit; original media is not copied.
- [x] Apple Books metadata through its local library database, with Full Disk Access guidance.
- [x] Explicit per-connector connection, reauthorization, health, pause/resume, manual sync, and full per-source deletion.
- [x] Permission descriptions in the generated app bundle.
- [x] Connector tests, full regression, and bundled-app verification.

## Boundaries

- No source content is sent to a cloud service.
- Calendar, Reminders, Contacts, and Photos use their supported macOS frameworks and consent flow.
- Safari, Messages, and Books remain read-only local-library readers. Messages and Books report a clear Full Disk Access requirement when macOS prevents access.
- Imported transcripts and Git repositories remain user-selected; Git work is deferred by product direction.
