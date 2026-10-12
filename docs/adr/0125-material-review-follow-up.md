# 0125. Material review follow-up: the cases ADR 0124 missed

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked to verify that every finding was addressed); agent (the details below)

## Context

An independent check of [ADR 0124](0124-material-review-accessibility-and-consistency.md)'s fixes, in the code and in
the running app, found cases like the ones fixed that had been missed, and a few regressions of the fixes.

## Decision

- **Lists**: the list's item styles reach only its own items (`.list > li`), so the choices of a dialog opened from a
  row are not drawn as list items, and a dialog's actions keep the dialog's spacing inside a row.
- **One-line titles**: the full-screen dialog's title ends in an ellipsis, as the app bar's does.
- **Type**: the remaining small text (day and week dates, intensity chips, the progress table's caption, the zones
  page's help) gets M3's line height and tracking.
- **Live region**: the sync problems banner and the person finder's result are read out through it too, instead of a
  `role="status"` added with its text.
- **Touch targets**: the phone calendar's 40px add button gets the 48px target; a date picker day fills its 48px cell,
  its 40px circle drawn inside a transparent border.
- **Contrast**: a week without an intensity shows its slider with a quieter handle instead of fading it to 38%, which
  read as disabled.
- **Regressions of ADR 0124**: icon buttons in a button group fade between states again; a keyboard press keeps the
  pressed layer (only a pointer press hands it to the ripple); wrapped rows of chips are 16px apart, so their targets
  meet without overlapping; disabled icon buttons win over the app bar's and snackbar's colours.

## Consequences

- Left as they are: with a mouse, the wide calendar's faint add buttons stay 32px (a 40px target), above WCAG 2.5.8's
  24px; a snackbar's timer waits while any snackbar is pointed at, not only its own, which can only delay a delete.
