# 0061. Harmonized custom colours for training intensity

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (chose harmonized green and amber over baseline roles only)

## Context

[ADR 0045](0045-material-baseline-colors.md) dropped every custom colour, so training intensity and workout kinds
used primary (easy), tertiary (medium) and error (hard). Using the error role for "hard" says something is wrong
when it is not, which Material Design 3 (M3) advises against. M3 allows a few custom colours, "harmonized" toward the
scheme's primary so they sit with it, each with the same four roles as the scheme's own colours.

## Decision

Three custom colours, generated with Google's `material-color-utilities` (`customColor`, `blend: true`) from the
baseline primary `#6750a4`: green (`#2e7d32`) for low, amber (`#f9a825`) for medium and red (`#d32f2f`) for high
intensity. Each has `--md-custom-color-<name>`, `-container` and `-on-<name>-container`, for light and dark. Workout
kinds' bars and the intensity values use the colour; intensity chips are filled with its container; the goal meter
over its goal uses medium. "Missed" on Today stays error-container: a missed workout is a problem.

## Consequences

- Easy, medium and hard read as green, amber and red again, in a shade that fits the purple scheme.
- ADR 0045's "no custom colours" now has this exception besides Strava's orange.
