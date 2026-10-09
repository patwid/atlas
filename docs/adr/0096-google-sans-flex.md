# 0096. Google Sans Flex instead of Roboto Flex

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked for the typeface as part of moving to Material 3 Expressive); agent (the details)

## Context

[ADR 0079](0079-bundled-roboto-flex-badge-text-and-app-bar-height.md) bundled Roboto Flex, the baseline M3 typeface.
Google's Material 3 Expressive apps are set in Google Sans Flex, which is on Google Fonts under the SIL Open Font
License 1.1 ([google/fonts `ofl/googlesansflex`](https://github.com/google/fonts/tree/main/ofl/googlesansflex)), so it
can be bundled the same way. It is variable in weight, width, optical size, slant, grade and roundness (`ROND`).

## Options considered

1. **Keep Roboto Flex.** It is 34 KB, but the app would keep the baseline M3 look in its most visible part, the text.
2. **Google Sans Flex, Latin subset, weight axis only (chosen).** 50 KB as WOFF2, from Google Fonts' `css2` API
   (`wght@100..1000`). It has the same unicode range as before.
3. **The same with the roundness axis.** 71 KB. Rounded headlines are an Expressive flourish that nothing in the
   app needs yet.

## Decision

- `frontend/assets/fonts/google-sans-flex-latin.woff2` replaces `roboto-flex-latin.woff2`, and `fonts/OFL.txt` is
  Google Sans Flex's licence. `--md-ref-typeface` names Google Sans Flex first, then Roboto and the system fonts.
- The M3 type scale's sizes, weights and line heights stay as they are.

## Consequences

- The first download and the shell cache grow by 16 KB. The precache list is built from the files, so nothing else
  changes.
- Other scripts still fall back to the system font. Adding roundness later means fetching the font again with
  `ROND` in the axis list.
