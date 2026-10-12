# 0113. No sync row in Settings; unusable device storage as a banner on every page

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked whether the Sync row could go); agent (the details below)

## Context

[ADR 0055](0055-material-review-quick-fixes.md) made the sync state a row of the Settings list. The row has no action
and opens nothing; it shows one line for the sync runner's phase. Most of what it says is shown better elsewhere:

- Ready without problems: always the same sentence, an explanation rather than a state.
- Ready with problems: the badge on the Settings tab and the problems banner on every Settings page (0049, 0055).
- Loading: the progress bar under the app bar (0048, 0095).
- Not loaded: only while signed out, when Settings cannot be reached.

The exception is the device database that cannot be opened (`Unavailable`): the app then looks empty and nothing
syncs, and the row was the only place that said so, on a page the user has no reason to visit.

(0112 was used by a change that was reverted; this record takes the next number to keep the history unambiguous.)

## Options considered

1. **Keep the row** — harmless, but a row that never changes and only repeats what the badge, banner and progress
   bar show.
2. **Drop the row and show `Unavailable` as a banner on Settings** — but an empty Home screen is where the user
   notices, not Settings.
3. **Drop the row and show `Unavailable` as an error banner at the top of every page (chosen).**

## Decision

- Settings has no sync row; its list is the account row followed by the sections. This changes the Settings part of 0055.
- When the device database cannot be opened, an error banner (`role="alert"`) at the top of every page says "This
  browser could not open its local storage, so nothing is shown or synced. Try reloading." It has no action.
- The problems banner and the full-device banner stay on the Settings pages as before (0049).
- The unused `Sync` icon is removed.

## Consequences

- Settings is one row shorter; nothing that the row showed is lost.
- A broken device database is seen at once instead of only on Settings.
