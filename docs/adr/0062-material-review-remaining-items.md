# 0062. Material review, remaining items: a choice dialog, chips, the phone calendar, the medium app bar

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked to go ahead with the Material review's next steps); agent (the details below)

## Context

The last items of the Material Design 3 (M3) review ([ADR 0055](0055-material-review-quick-fixes.md)) after the
larger ones ([ADR 0056](0056-menus-and-undo.md)-[0061](0061-harmonized-intensity-colours.md)).

## Decision

- **Choosing an activity on Today** is M3's simple dialog instead of a list opened inside the workout: the headline
  "Which activity was it?", one row per activity, taken at once, and Cancel. It opens when drawn, through the same
  `data-open` attribute as the form dialogs ([ADR 0057](0057-forms-in-full-screen-dialogs.md)).
- **Chips, not badges**: `atlas/ui/badge` is `atlas/ui/chip` (`chip.label`, `chip.with_icon`, `chip.row`), with the
  CSS class `label-chip`. In M3 a badge is a notification count, like the one on the Settings tab.
- **The calendar on a phone**: a week's label stays under the app bar and the plan's tabs while its days scroll by
  (`overflow: clip` on the week instead of `hidden`, which would stop `position: sticky`), and a day without
  workouts takes less room.
- **Medium app bar**: on a plan's or an athlete's page the app bar has the name on a line of its own in
  headline-medium, under the back button and the actions; once the page scrolls it becomes the small bar.

## Consequences

- With this the review's list is done. Not adopted, as decided in the review: M3's own date picker year list and
  range picker, a bottom sheet for anything but the calendar's details, and Expressive toolbars, FAB menus and split
  buttons.
