# 0080. A workout or activity you can change opens in its form, with Delete there

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (reviewed the edit workflow and chose this option); agent (the details below)

## Context

On the plan calendar ([ADR 0066](0066-plan-calendar-without-a-sidebar.md)) pressing a workout opened a details
dialog, and its Edit opened the form dialog over it; saving or cancelling went back to the details dialog, which then
had to be closed. Changing a workout took four presses, stacked two dialogs (which Material Design advises against),
and the details dialog showed the owner little the calendar card does not. Activities worked differently: a row did
nothing when pressed, and Edit and Delete were in its menu ([ADR 0056](0056-menus-and-undo.md)).

## Options considered

1. **The owner's press opens the form; others get the details dialog (chosen)** — one dialog, two presses.
2. **Edit replaces the details dialog instead of stacking on it** — no stacking, but still three presses.
3. **Editing inside the details dialog** — a view and an edit state in one dialog, for little over option 1.

## Decision

- **Workouts**: for someone who can edit the plan, pressing a workout opens its form dialog
  ([ADR 0057](0057-forms-in-full-screen-dialogs.md)); Save or Cancel goes back to the calendar. Anyone else gets the
  read-only details dialog, now without actions.
- **Activities**: pressing a row of one's own activity entered by hand opens its form, the whole row being the target
  (its headline is a button drawn like the row links of [ADR 0069](0069-subheaders-row-links-and-empty-states.md)).
  The row menu is gone. Strava activities, which cannot be changed, open nothing.
- **Delete** is an icon button in the form dialog's top bar while editing (`form_dialog.view_with_action`), for both;
  it closes the form and keeps the Undo snackbar.

## Consequences

- Workouts and activities open the same way. Deleting takes one press more (open, then Delete), which Undo made safe
  anyway.
