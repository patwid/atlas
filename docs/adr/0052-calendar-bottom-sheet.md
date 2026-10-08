# 0052. The plan calendar's sidebar as a bottom sheet on smaller screens

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked for a bottom sheet); agent (the details below)

## Context

The plan calendar ([ADR 0043](0043-plan-phases-goal-and-calendar.md)) shows the open workout, the selected week and
the plan's settings in a sidebar beside the calendar from 72rem up. Below that the sidebar followed the calendar, so
on a phone picking a week or workout showed its details far below, out of sight; focusing the form scrolled there
and away from the calendar. Material Design 3 (M3) uses a standard bottom sheet for supporting content like this.

## Options considered

1. **Keep the sidebar under the calendar** — no work, but the details stay out of sight on a phone.
2. **A modal bottom sheet** — a scrim over the calendar, so the calendar cannot be used while the details show.
3. **A standard (non-modal) bottom sheet (chosen)** — stays docked above the navigation bar, collapsed to its handle
   and a one-line summary, so the calendar stays usable with it open.

## Decision

- Below 72rem the sidebar is fixed above the navigation bar with M3's sheet shape (28px top corners, a drag handle,
  surface-container-low). Collapsed, it shows the handle and a summary: the open workout's title, "New workout", or
  the selected week. Expanded, it shows the panels, up to 65% of the screen's height, scrolling inside.
- The handle is a button with `aria-expanded` and `aria-controls`; pressing it sends `SheetToggled`. The model keeps
  `sheet_expanded`; selecting a week or workout, adding or editing a workout, and editing the plan's settings
  expand it. Collapsed content is hidden (`visibility`), so it is not reachable by keyboard.
- Dragging the handle up or down by more than 30px opens or closes the sheet (`atlas/ui/interaction`); the drag
  clicks the handle, so the page's message does the work and the state stays in the model.
- From 72rem up nothing changes: the handle is hidden and the sidebar sits beside the calendar.

## Consequences

- On a phone, details appear over the calendar instead of below it; the calendar keeps room under the sheet's
  collapsed height so its last week can be scrolled into view.
- The sheet does not follow the finger while dragging; it opens or closes when the drag ends.
