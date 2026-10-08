# 0045. Use Material Design 3's baseline colors only

- Status: Accepted. Intensity's colours are changed by [0061](0061-harmonized-intensity-colours.md).
- Date: 2026-10-08
- Deciders: owner (asked to drop all custom colors for Material Design defaults); agent (the role mapping below)

## Context

[ADR 0044](0044-material-design-3-styling.md) styled the app after Material Design 3 (M3) with a scheme generated
from Atlas's former Bootstrap blue (`#0d6efd`), plus colors of its own: green and amber for training intensity, tinted
mixes for the plan phases, and hex values for the shadows, the dialog scrim, the select arrow, the app icon and the
browser's theme color. The owner wants no custom colors: M3's defaults only.

## Options considered

1. **M3's baseline scheme, every app color mapped onto one of its roles (chosen)** — the scheme M3 ships with
   (primary `#6750a4`), as published in Google's `@material/web` tokens (M3 34.0), light and dark.
2. **A scheme generated from the baseline seed `#6750a4` by `material-color-utilities`** — the newer tonal-spot
   algorithm gives slightly different values from the published baseline (primary `#65558f`), so it is not the
   default the owner asked for.

## Decision

We use the M3 baseline scheme unchanged, and every color in `app.css` is an M3 color role:

- **Intensity and workout kinds** (ADR 0043), which M3 has no roles for: low is `primary`, medium `tertiary`, high
  `error`. The weekly goal meter over its goal uses `tertiary`.
- **Phase bands**: `surface-container-low`, `-high` and `-highest` for base, pre-competition and competition; their
  titles name them.
- **Shadows and scrim** are the `shadow` and `scrim` roles; the select arrow is drawn in CSS in `on-surface-variant`.
- **Theme color** (browser bar, manifest) is the baseline `surface` of each scheme; the app icon is the baseline
  `primary`.
- **Exception**: Strava's orange on "View on Strava" stays, since Strava's brand rules require it (ADR 0027).

## Consequences

- The app is M3 purple instead of blue, and there is one place to change colors: the `--md-sys-color-*` values.
- Intensity loses its green/amber/red traffic-light reading: easy and hard are told apart by M3's primary, tertiary and
  error instead, and still by their labels and percentages.
- If the owner wants a brand color later, a scheme generated from a seed replaces the baseline values without other
  changes (as ADR 0044 did).
