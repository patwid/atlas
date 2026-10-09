# 0079. Roboto Flex served with the app, the badge read out, and sticky offsets from the app bar's height

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's other items); agent (the details below)

## Context

- `app.css` named Roboto Flex first in its type stack ([ADR 0044](0044-material-design-3-styling.md)) but never
  loaded it, so nearly every device drew the app in its system font, while the M3 type scale's sizes and weights were
  set for Roboto.
- The Settings tab's sync-problem badge ([ADR 0055](0055-material-review-quick-fixes.md)) carried its words in an
  `aria-label` on a `span`, which screen readers generally do not read, so it was heard as a bare number.
- A plan's tabs stuck at `top: 4rem` and the phone calendar's week labels at `top: 7rem`
  ([ADR 0062](0062-material-review-remaining-items.md)), while the app bar grows by the status bar's safe area in an
  installed app on a phone with a notch, so they slid under it there.

## Options considered (typeface)

1. **Serve Roboto Flex from `pb_public` (chosen)** — the Latin subset with only the weight axis is 34 KB as WOFF2,
   precached by the service worker, so it works offline; no request to another host. Licensed under the SIL Open Font
   License 1.1, which allows bundling with its licence.
2. **Load it from Google Fonts** — a third-party request on every first visit (and an issue for privacy in the EU and
   Switzerland), and not available offline.
3. **Drop it from the stack and use the system font** — nothing to load, but the type scale would keep not looking as
   designed.

## Decision

- `frontend/assets/fonts/roboto-flex-latin.woff2` (from Google Fonts, Latin subset, `wght` 100–1000) with
  `fonts/OFL.txt`, declared with `@font-face` and `font-display: swap`. Other scripts fall back to the system font.
- The badge's number is `aria-hidden`; visually hidden text after the tab's name says ", 3 sync problems".
- `--app-bar-height` is the small app bar's height including the safe area; a plan's tabs stick at it and the week
  labels 3rem (the tabs) below it.

## Consequences

- 34 KB more in the first download and the shell cache. Updating the font means fetching the file again the same way.
