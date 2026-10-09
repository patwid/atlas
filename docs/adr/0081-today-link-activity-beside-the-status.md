# 0081. Today: "Link activity" as a text button beside the status

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to improve the Link an activity button); agent (the details below)

## Context

On Today ([ADR 0026](0026-today-screen.md), [0073](0073-today-order-details-and-menu.md)) a workout to do today or a
missed one had an outlined "Link an activity" button on a line of its own under its status chip. The "To do" chip is
outlined too, so the two looked alike: the chip like a button, the button like another label. The button sat outside
an actions row, tight against the item's bottom edge, unlike Confirm and Choose another on a suggested activity, and
in the last seven days every missed workout added one more outlined button.

## Decision

- The action follows the status chip on its line: a text button with the link icon, "Link activity".
- A suggested activity keeps its status line ("Looks done" and what was run), then an actions row with Confirm
  (filled) and Choose another, now a text button.
- A confirmed link keeps its menu.

## Consequences

- Chips are labels and actions are text in the primary colour, so they no longer look alike; items without a choice
  to make are a line shorter.
