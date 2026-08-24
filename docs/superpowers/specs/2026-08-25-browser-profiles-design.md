# Browser Profiles Connector Design

## Goal

Replace the Safari connector with one explicit Browser Profiles connector backed by a catalog of supported installed browsers and local profile layouts.

## Consent and configuration

- The user enables Browser Profiles and confirms one browser-specific permission boundary.
- MacBrain then discovers profiles only inside known local storage roots for catalogued browser families; it never scans arbitrary applications.
- Every discovered profile gets its own local source and can be paused or deleted like every other local source.
- Repeating Browser Profiles discovery synchronizes existing matching profiles and adds newly found profiles without duplicates.
- Existing Safari records migrate to the Browser Profiles kind but do not gain a profile path; they remain inactive until Browser Profiles is enabled.

## Data captured

- Chromium-family browsers: `Bookmarks` JSON for bookmarks and Reading List, `History` SQLite for visited pages and downloads, and an optional current-tab snapshot from the running browser through macOS Automation.
- Firefox-family browsers: `places.sqlite` for bookmarks, history, downloads, and Reading List-like bookmark entries where present; an optional current-tab snapshot is attempted through macOS Automation when Firefox exposes it.
- Safari: `Bookmarks.plist` for bookmarks and Reading List, plus an optional current-tab snapshot through macOS Automation.
- An unavailable browser, locked local database, or declined Automation permission does not remove previously indexed browser content. It records source health and continues indexing data that remains readable.

## Documents and provenance

Each normalized document stores browser, profile name, data type (`bookmark`, `history`, `readingList`, `download`, or `openTab`), URL, title, and timestamp when available. Browser history is bounded per sync to prevent an unbounded first index; bookmarks, reading list, downloads, and current tabs are complete for readable data.

## Privacy

All browser data stays local. Current-tab capture requires the selected browser to be running and macOS Automation permission for that browser. MacBrain shows a clear source description before consent and never silently accesses unrelated applications or unknown browser storage.
