# MacBrain onboarding phase

## Goal

Make first launch feel like a guided Mac setup, not a developer checklist. Users should understand what MacBrain needs, why it needs it, what remains optional, and what is already working.

## First-launch experience

- [ ] Add dedicated onboarding before chat.
- [ ] Explain selected context stays on-device.
- [ ] Present one **Set up MacBrain** action before source management.
- [ ] Request Contacts, Calendar, Reminders, Photos, then Apple Events for Notes and Mail.
- [ ] Show sync progress without private source content.
- [ ] Allow **Continue with limited context** for every optional step.
- [ ] Persist completion; allow reopening from Settings.

## Full Disk Access

Messages and some browser libraries can need Full Disk Access; macOS requires user approval in System Settings.

- [ ] Detect missing access before protected browser-library or Messages indexing.
- [ ] Explain what access enables and why macOS requires it.
- [ ] Add **Open Full Disk Access Settings**.
- [ ] Display exact MacBrain bundle to add, with copy-path.
- [ ] Recheck access and begin sync automatically when user returns.
- [ ] Keep Notes, Mail, Calendar, Reminders, Contacts, and Photos usable without it.

## Source health and recovery

- [ ] Replace technical statuses with clear user-facing language.
- [ ] Show compact setup states: ready, waiting, optional, unavailable.
- [ ] Add **Allow**, **Open Settings**, **Retry**, and **Skip for now** actions.
- [ ] Explain local Apple Books availability.
- [ ] Treat empty Calendar/Reminders libraries as healthy.
- [ ] Provide **Check setup again** after permission changes.

## Privacy and quality

- [ ] State what every source indexes and excludes before consent.
- [ ] Let users enable sources individually after onboarding.
- [ ] Provide pause, delete, and reindex for every source.
- [ ] Add local-storage, no-cloud-sync, and deletion summary.
- [ ] Test no, partial, and full permissions; rejection; Settings return; each supported macOS release.
