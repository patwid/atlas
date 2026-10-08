# 0054. Material 3 date and time pickers beside the native fields

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked for Material Design date and time pickers); agent (the approach below)

## Context

Three fields take a date or a time: an activity's day and start time, and the first day of a plan when it is
started or assigned. They are native `<input type="date">` and `<input type="time">`: typeable, validated by the
browser, and with the browser's own picker, which looks different on every platform and nothing like Material
Design 3 (M3). [ADR 0047](0047-more-material-components.md) left M3's pickers out as costly to build.

## Options considered

1. **Keep the native pickers** — no work, but the one part of the forms that does not look like M3.
2. **Replace the fields with M3 text fields and pickers only** — typing a date would need our own parsing and
   validation, and tests and keyboard users lose the native field's typing.
3. **Keep the native fields and add M3's modal pickers behind a button at the field's end (chosen)** — typing works
   as before; the picker is a second way in.

## Decision

- `atlas/ui/date_picker`: M3's modal date picker in a native `<dialog>` (opened with `dialog.show`, so Escape and a
  click outside close it): "Select date", the chosen date as headline, the month with previous and next buttons, a
  grid of days from Monday (today outlined, the chosen day filled), Cancel and OK. The grid follows the ARIA grid
  pattern with one tab stop: arrow keys move a day or a week, Page Up and Page Down a month, Home and End to the
  week's ends.
- `atlas/ui/time_picker`: M3's modal time picker with a dial, 24-hour as the app shows times: the hour and minute as
  large fields, the outer ring 12 and 1 to 11, the inner ring 00 and 13 to 23 (as on Android). Picking an hour moves
  on to the minutes, offered in steps of 5; the arrow keys change the hour or minute by one, so any minute can be
  set with the keyboard.
- Each picker has its own `State` and `Msg`, embedded by the page (`activities_page`, `assignments_page`); its
  `update` returns the picked text (`2026-11-17`, `18:45`) on OK, which the page puts in the field as if typed. The
  picker opens on what the field holds when its button is pressed (read in `update`, not when the button was
  drawn). Its dialog sits beside the page's form, since a dialog's `method="dialog"` form cannot be inside another
  form.
- `field.with_trigger` puts the picker's icon button (calendar or clock) at the field's end; the browser's own
  picker button is hidden where CSS allows (Chrome, Edge, Safari).
- Not built: the year list, the date range picker, and the pickers' text input mode (the field itself is that).

## Consequences

- Firefox still shows its own calendar button in date fields next to ours; both work.
- The whole-app tests' `<dialog>` polyfill now closes a dialog when a `method="dialog"` form in it is submitted, as
  browsers do.
- Dates and times stay in the fields' formats (`YYYY-MM-DD`, `HH:MM`), so nothing else changes.
