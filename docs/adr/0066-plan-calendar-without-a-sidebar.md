# 0066. The plan calendar without a sidebar: week and workout dialogs, settings in the plan's Edit

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to drop the plan's sidebar and chose the proposed alternatives)

## Context

The plan calendar ([ADR 0043](0043-plan-phases-goal-and-calendar.md)) had a sidebar with three panels: the open
workout, the selected week (intensity, distance against the goal, time, workouts) and the plan's settings (phases
and goal). From the large window class it sat beside the calendar and took a fifth of the width; below it, it was a
bottom sheet ([ADR 0052](0052-calendar-bottom-sheet.md)). The plan's settings duplicated the plan's Edit dialog,
which already has the phases and the goal.

## Options considered

1. **Keep the sidebar** — no work, but it takes width from the calendar and needs the bottom sheet on smaller screens.
2. **Expand weeks and workouts in place** — no overlay, but rows of a seven-column grid would jump around.
3. **Put each panel where it belongs (chosen)**: the plan's settings in its Edit, a week's figures in its row and its
   details in a dialog, a workout in a dialog.

## Decision

- **Plan settings**: the sidebar's panel and its editing go; the phases and the goal are changed with the plan's Edit
  ([ADR 0058](0058-plan-page-tabs-and-app-bar-actions.md)). The plan's page sums them up under its description:
  "12 weeks: 4 base, 4 pre-competition, 4 competition · 40.00 km a week" (`plans_page.summary`).
- **Weeks**: each week's row shows its distance against its goal ("16.00 km / 32.00 km", the goal scaled by its
  intensity, [ADR 0064](0064-intensity-scales-the-weekly-goal.md)) with a small bar, for every week at once. Pressing
  the row opens the week's dialog: its phase, the intensity slider (the owner's), its distance, time and workouts, and
  the goal meter.
- **Workouts**: pressing one opens its dialog: week and day, kind, targets and notes, with Delete and Edit for the
  owner. Edit opens the form dialog ([ADR 0057](0057-forms-in-full-screen-dialogs.md)) over it; saving or cancelling
  the form returns to it. Closing the form must not end the edit, so the workout's dialog closing only ends a viewing.
- `dialog.details` draws these basic dialogs: declarative (`data-open`, as the form dialogs), and closed by Escape,
  Close or a click outside them (the form dialogs still ignore outside clicks).
- The sidebar, the bottom sheet, its swipe handling and its styles are removed; the calendar has the full width at
  every size.

## Consequences

- ADR 0052 is superseded; ADR 0043's sidebar is replaced by these dialogs.
- Setting the intensity of several weeks means opening each week's dialog in turn.
