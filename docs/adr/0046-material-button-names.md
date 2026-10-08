# 0046. Name buttons after Material Design 3 and drop the danger button

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked to switch primary, danger etc. to their Material equivalents); agent (the mapping below)

## Context

[ADR 0044](0044-material-design-3-styling.md) kept `atlas/ui/button`'s Bootstrap-era names (`primary`, `secondary`,
`danger`, `link`) and only restyled them as M3 buttons. Material Design 3 names its
[common buttons](https://m3.material.io/components/buttons/overview) by emphasis (elevated, filled, tonal, outlined,
text) and has no danger or destructive button. Its [dialogs](https://m3.material.io/components/dialogs/guidelines)
put both actions in text buttons, the dismissive action before the confirming one.

`danger` was used for the confirming action of all eight confirmation dialogs, and once for a plan's Delete button
outside a dialog; the dialogs' dismissive action came second, and was a filled button in the plan dialog.

## Options considered

1. **Keep the names, restyle only (ADR 0044)** — no churn, but the code speaks Bootstrap while the screen is M3, and
   `danger` keeps a red button M3 does not have.
2. **Rename to M3 names and follow M3's dialog guidance (chosen)** — `filled`, `outlined`, `text`; no `danger`.
3. **Also add `elevated` and `tonal`** — nothing uses them yet; they can be added when a screen needs one.

## Decision

`atlas/ui/button` offers `filled`, `outlined` and `text` (plus the unstyled `button` for Strava, ADR 0027):

- `primary` becomes `filled`, `secondary` becomes `outlined`, `link` becomes `text`.
- `danger` is removed, with its `.md-button-danger` style. In the confirmation dialogs both actions are text buttons,
  the dismissive one ("Keep it") first and the confirming one ("Yes, delete it") last. The plan's Delete button is
  outlined, like Delete for workouts and activities.

## Consequences

- Destructive actions are no longer red; they are guarded by the dialog and its wording ("Yes, delete it").
- With the dismissive action first, it is the dialog's first focusable control and takes focus when the dialog
  opens, so pressing Enter right away keeps the item.
- New buttons are chosen by M3 emphasis; `elevated` and `tonal` are added to the module when first needed.
