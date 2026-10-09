# 0056. Menus for item actions, and Undo instead of confirming deletes

- Status: Accepted. Activities are edited and deleted from their form since [0080](0080-open-items-in-their-form.md).
- Date: 2026-10-08
- Deciders: owner (chose Undo over confirmation dialogs); agent (the details below)

## Context

The Material review ([ADR 0055](0055-material-review-quick-fixes.md)) found two patterns that are not Material
Design 3 (M3):

- Each activity, schedule entry, coach and share showed its actions as a row of outlined buttons in the list item.
  M3 puts an item's actions in a menu at the end of its row.
- Every delete asked first in a dialog. M3 asks only for actions that cannot be taken back; for those that can, it
  acts at once and offers Undo in a snackbar. Deletes in Atlas can be taken back: rows are soft-deleted (ADR 0014)
  and go through the outbox (ADR 0016).

## Options considered

1. **Undo by undeleting on the server** — write the delete at once, and on Undo write `deleted: false` with a new
   base. Needs a conflict-safe undelete path through sync and the server's rules.
2. **Undo by waiting (chosen)** — hide the item at once and write the delete only when the Undo snackbar goes (after 6
   seconds, when it is closed, or when another delete starts). Undo just cancels; nothing was written.

## Decision

- `atlas/ui/menu`: an icon button (⋮) with a native `popover` menu of items (icon and label). The browser closes it
  on Escape, a click outside and when an item is chosen; `atlas/ui/interaction` places it under its button (above
  it when there is no room) and moves between items with the arrow keys, Home and End.
- Item actions move into menus: activities (Edit, Delete), schedule entries (Change date, Remove), coaches (Remove
  access) and shares (Stop sharing).
- `atlas/ui/undo` keeps one waiting delete per page and draws its snackbar ("Activity deleted · Undo"). Plans,
  workouts, activities and schedule entries delete this way; deleting a plan also goes back to the plan list, where
  the snackbar shows. The delete is looked up when it is written, among all rows, so it is written even if another
  plan is open by then.
- Unlinking an activity on Today happens at once (whether a workout is done is worked out from the stored matches
  outside the page, so hiding a waiting unlink is not possible there); its Undo links the same activity again.
- Disconnect Strava, Remove access and Stop sharing still ask first: they cannot be undone.
- `snackbar` gains a button action (`Act`) besides a link.

## Consequences

- If the app is closed while a delete waits, the delete is not written and the item stays: the safe way to fail.
- A deleted item's other effects (for example a deleted workout still showing on Today) wait the few seconds too.
- Tests close the snackbar to write a delete without waiting, and check Undo writes nothing.
