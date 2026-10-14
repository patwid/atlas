# 0132. Draw every page's controls through `atlas/ui`

- Status: Accepted
- Date: 2026-10-14
- Deciders: owner, agent

## Context

Since ADR 0040 the markup of Atlas's controls lives in small modules under `atlas/ui`, so a class name or an ARIA
attribute is written once (`atlas/ui/button`: "every button in the app still goes through this module"). Six modules
still drew some controls with raw `lustre/element/html` and hand-typed `md-*` classes: `home_page` (the simple dialog
for linking an activity, its choices and a text-button link), `workout_fields` (the rep intensity slider),
`goals_page` and `activities_page` (list rows that open a form dialog; the hidden FIT file input), `workouts_page`
(the week's intensity slider and the calendar's week, workout and add buttons) and `shell` (the offline icon button,
the back link and the sync progress bar). The two intensity sliders were near copies.

## Options considered

1. **Leave them** — they work. But the markup drifts: a fix in a `ui` module misses the copies.
2. **Move them onto `atlas/ui`**, adding what is missing.

## Decision

We will draw these controls through `atlas/ui`, with these additions:

- `button.text_link` and `button.icon_link`: links that look like a text or icon button.
- `layout.row_button`: a list item's headline that opens a dialog, beside `row_link` for one that opens a page.
- `dialog.simple`, `dialog.choices` and `dialog.choice`: M3's simple dialog (ADR 0062). The dialog now carries the id
  its headline's id is built from.
- `field.file`: the hidden file input a button opens (ADR 0100).
- `progress.linear`: the indeterminate linear progress bar (ADR 0048).
- `slider` (new): a labelled M3 slider with its value and help or error line, and a read-only form (ADR 0051).

Buttons with a look of their own, such as the calendar's, use `button.button`, the unstyled base.

## Consequences

No page outside `atlas/ui` builds a `button`, `input`, `select`, `textarea`, `dialog` or `label` itself, nor types an
`md-*` class. The markup is unchanged apart from the simple dialog's id. A new control goes into `atlas/ui` first.
