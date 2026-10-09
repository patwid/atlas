# 0086. Form dialogs below the screen's height, and date and time inputs drawn plainly

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (found the dialogs too tall on larger screens and the picker buttons misaligned); agent (the details
  below)

## Context

- From 600px a form dialog ([ADR 0057](0057-forms-in-full-screen-dialogs.md), [0085](0085-form-dialog-spacing-pairs-and-buttons.md))
  could grow to the screen's height less 3rem, so the plan form, the longest, filled the screen from top to bottom.
  The owner weighed pages of their own for plans and activities and chose to keep dialogs for now.
- The buttons at the end of the date and time fields ([ADR 0054](0054-material-date-and-time-pickers.md)) sit 8px
  from the top of a 56px field. Browsers draw date and time inputs their own way (Safari centres the value and sizes
  the box to it; Chrome adds padding inside), so those inputs need not be 56px and the button was off their middle.

## Decision

- From 600px a form dialog is at most 40rem high and leaves 4rem above and below; a longer form scrolls between its
  headline and its buttons.
- Date and time inputs with a picker button have no native appearance and a fixed 56px height, with the browser's
  inner padding removed and the value at the start.

## Consequences

- The page shows around a dialog on larger screens, so it reads as a dialog. The plan form scrolls a little there.
- The change to the inputs could not be checked in a browser in the sandbox; if a browser still draws them off, its
  own pseudo-elements are the place to look.
