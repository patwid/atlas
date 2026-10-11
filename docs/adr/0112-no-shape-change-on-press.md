# 0112. Buttons and rows keep their shape while pressed, held or hovered

- Status: Accepted
- Date: 2026-10-11
- Deciders: owner (buttons sometimes looked off and changed shape when pressed and held); agent (the details below)

## Context

[ADR 0053](0053-material-3-expressive.md) made buttons, icon buttons and the FAB square off to the small corner while
pressed, tightened a segmented button's inner corners while pressed, and rounded a list row further on hover, press
and focus. [ADR 0098](0098-medium-buttons-and-button-group.md) added the medium button's square-off and a button
group in which the pressed button widens and its neighbours narrow.

On a touch screen these states are tied to `:active` and `:hover`, which stick: a long press keeps `:active` while the
finger rests (and while the browser's long-press handling runs), and a tapped element stays `:hover` until something
else is touched. A button or row is then left in its pressed or hovered shape, which looks broken, and the button
group's neighbours shift under the finger.

## Options considered

1. **Keep the morphs, limit them to `@media (hover: hover)`** — fixes sticky hover but not a held press on a phone,
   where the app is used most.
2. **Drop shape and size changes driven by press, hover and focus (chosen)** — the state layer and the ripple
   already show the press; shapes stay stable.

## Decision

- Buttons (all sizes), icon buttons, the FAB, segmented buttons and list rows keep their shape while pressed, held,
  hovered or focused. Pressing shows only the state layer and the ripple.
- The button group's buttons keep their width while pressed.
- Shapes that show a state stay: the selected segmented button is fully round, a selected chip takes the medium corner.
- This replaces the press and hover shape parts of 0053 and 0098; the rest of both stands.

## Consequences

- Less Expressive motion on press, but nothing is left looking half-pressed on a phone.
- If press morphs come back, they need a pointer-event based pressed state that ends on `pointercancel` and
  `contextmenu`, not `:active`.
