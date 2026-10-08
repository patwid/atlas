# 0048. Material back button, progress indicators and status chips

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (agreed to the agent's proposal); agent (the details below)

## Context

After [ADR 0047](0047-more-material-components.md), three places still did not follow Material Design 3 (M3):

- A plan's and an athlete's page had a "← All plans" / "← All athletes" text link at the top of the page; in M3 the
  way up is a back arrow at the start of the top app bar.
- Work in progress was plain text ("Checking…" for Strava, "Copying…" for a plan copy), and a running sync was not
  shown at all.
- Today's state of a workout (rest day, to do, missed, looks done, done) was a plain paragraph, so the day's state
  did not stand out.

## Options considered

1. **Leave them** — no work, but they stay outside the M3 look and a sync stays invisible.
2. **Hand-write the M3 equivalents (chosen)** — same approach as ADR 0044 and 0047.

## Decision

- **Back button**: `atlas/shell` puts an icon button (arrow back, `aria-label` "All plans" / "All athletes") at the
  start of the app bar on `Plan` and `Athlete` routes, linking to the tab's list. The pages drop their own link.
- **Linear progress**: the shell gets a `syncing` flag (`syncing.is_busy`: the device database is loading or a sync
  run is going on) and shows an indeterminate linear indicator along the bottom of the app bar, with
  `role="progressbar"` and the label "Syncing". It fades in after half a second, so a quick sync does not flicker.
- **Circular progress** (`atlas/ui/progress.circular`): a spinner next to "Checking…" and "Copying…"; the text stays
  the announced status, the spinner is decorative.
- **Status chips** on Today: the state is a chip in an M3 color role (missed: error container, looks done: tertiary
  container, done: secondary container, to do: outlined, rest day: surface container), with an icon, and the
  activity's summary follows as plain text instead of being part of one sentence ("Done: 07:00 · Run …").

## Consequences

- Pages inside a tab no longer render their own way back; tests look for it in the shell (`shell_test`).
- Tests that read "Done: …" as one text now check the chip and the summary separately.
- Every sync run shows in the app bar, so a sync that hangs is visible to the user.
