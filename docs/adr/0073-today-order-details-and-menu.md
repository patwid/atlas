# 0073. Today: the past week before the week ahead, shorter details, a menu for a confirmed link

- Status: Accepted. The order of the groups is changed by [0082](0082-today-newest-first.md).
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's other items); agent (the details below)

## Context

Today ([ADR 0026](0026-today-screen.md)) listed today, then the next seven days, then the last seven. The items that
ask for something, a missed workout or a suggested activity to confirm, are in the last seven days, so they were
below the week ahead. Every item repeated its plan's name and its date, also in the Today group and for someone who
follows one plan. A confirmed link had two outlined buttons, Change and Unlink, where activities have a menu
([ADR 0056](0056-menus-and-undo.md)). The dialog for a day without activities said to add one in Activities without
a way to get there.

## Decision

- The groups are Today, the last seven days (newest first), then Coming up.
- An item's details name its plan only when the user follows more than one, and its day only outside the Today group.
- A confirmed link's Change activity and Unlink are in a menu at the end of the item; Unlink keeps its Undo.
- The choosing dialog for a day without activities has a Go to activities button.

## Consequences

- What needs doing is in view first. Confirm and Choose another, for a suggested activity, stay as buttons: they are
  the item's main actions.
