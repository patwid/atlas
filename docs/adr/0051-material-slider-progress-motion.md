# 0051. Material slider and progress, a phone layout for the athlete table, calendar cards, ripple and motion

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked for the remaining Material Design 3 changes); agent (the details below)

## Context

The last differences to Material Design 3 (M3) after [ADR 0050](0050-chips-empty-states-button-icons.md):

- The week-intensity slider was the browser's own control in the primary color, and the goal and intensity meters
  were a plain bar.
- The coach's weekly table of an athlete needed sideways scrolling on a phone; M3 has no data table component.
- The plan calendar's workouts were flat boxes with a colored left border.
- Buttons, rows and tabs only faded a highlight; M3 draws a ripple from the touch point. Pages appeared without
  transition, and the app bar did not change when content scrolled under it.

## Options considered

1. **Leave them** — no work; they stay the least M3-like parts of the app.
2. **CSS where possible, and one small FFI for what needs the DOM (chosen)** — the ripple needs the pointer's
   position and the app bar needs the scroll position; everything else is CSS.
3. **A ripple that adds a node per press** — the usual technique, but Lustre owns the DOM; nodes it did not create
   could be removed or confuse its diff.

## Decision

- **Slider**: M3's current slider look in CSS: a 16px rounded track, the active part in primary, a 4px handle with a
  gap around it. Firefox draws the active part itself (`::-moz-range-progress`); for other browsers the view sets
  `--fill` on the input.
- **Linear progress** (goal and intensity meters): indicator, gap, the rest of the track, and a stop dot.
- **Athlete table**: stays a `<table>` (with its caption, column and row headers); under 40rem each week is a card
  of label and value pairs, the labels coming from a `data-label` on each cell.
- **Calendar**: workouts are small filled cards with rounded corners and their kind as a bar along the leading edge;
  the "add here" button is a pill with a tonal hover.
- **Ripple and app bar** (`atlas/ui/interaction`, installed once at start): a document-level `pointerdown` listener
  sets the ripple's position and size as CSS variables on the pressed button, row, chip or tab indicator and flips
  its `data-ripple` between `a` and `b` to restart a CSS animation; a scroll listener sets `data-scrolled` on
  `<html>`, which gives the app bar the surface-container color. Neither adds or removes nodes.
- **Page transition**: the page sits in a keyed element (keyed by its address), so a new page is a new element and
  fades in. Opacity only, since a transform would move the fixed FAB and snackbar while it runs.
- All animations stop with `prefers-reduced-motion`.

## Consequences

- `test-js/interaction.test.mjs` covers the FFI in jsdom.
- Moving between pages recreates the page's elements instead of reusing them; page state lives in the model, so
  nothing is lost.
- On a phone, some screen readers stop announcing the table as a table once its rows are drawn as blocks; the
  caption and the row and column headers stay in the markup.
