# Generic Browser Profiles connector

## Decision

MacBrain exposes one **Browser Profiles** connector. Choosing it and confirming is explicit consent for MacBrain to discover supported local browser profiles on the current Mac, create one local source per profile, run the initial sync, and refresh those sources through the normal five-minute background schedule.

This is browser-only consent. It does not discover, connect, or sync unrelated applications.

## Covered browser families

The catalog recognizes local profile layouts for Safari; Chrome and Chrome Canary; Chromium; Brave stable, Beta, and Nightly; Opera and Opera GX; Firefox stable, Developer Edition, and Nightly; Arc; Vivaldi; Microsoft Edge stable, Beta, Dev, and Canary; and Tor Browser where its profile root is known.

Dia uses a verified Chromium-compatible local profile root and is automatically indexed when Browser Profiles is enabled. Orion and DuckDuckGo remain catalogued but are not automatically indexed until stable, documented local profile layouts are verified. MacBrain must show no false success for an unavailable format.

## Data scope

For Chromium and Firefox profiles, MacBrain indexes locally stored bookmarks, history, Reading List where present, and downloads. It also requests open-tab snapshots from a running browser when macOS Automation permits it. Safari indexes bookmarks and Reading List from its local library plus open tabs when permitted. A browser only contributes data it exposes through a stable local format or Automation API.

## Unknown browser handling

After Browser Profiles is explicitly enabled, MacBrain also performs a bounded scan inside `~/Library/Application Support`. It creates a generic Chromium-compatible source only when it finds a conventional Chromium profile directory (`Default`, `Profile N`, Guest, or System Profile) containing a local browser signature such as `History`, `Bookmarks`, or `Preferences`. This supports browser brands MacBrain does not yet name directly without treating arbitrary application folders as browser data. Generic profiles do not request open-tab Automation because there is no verified application target.

Unknown WebKit, Firefox, encrypted, or nonstandard layouts remain unindexed until a verified adapter exists. They must be shown as unsupported rather than guessed.

## Safety and lifecycle

- No browser scanning occurs at app launch.
- One confirmed action discovers profiles under known storage roots only.
- Repeating the action re-syncs matching profiles and adds newly found profiles without duplicating them.
- Each discovered profile remains separately visible, pausable, and deletable in Connected sources.
- Unsupported or unknown browser storage is reported honestly instead of being guessed or broadly scraped.
