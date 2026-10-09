# 0085. Form dialogs: one spacing, pairs only where they fit, buttons at the bottom on wider screens

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (found the New plan and New activity dialogs off); agent (the details below)

## Context

The form dialogs ([ADR 0057](0057-forms-in-full-screen-dialogs.md)) for a plan, an activity, a workout and starting a
plan had these problems, read from their code and CSS:

- Fields were 8px apart, chip groups and the phases 12px. A floating label rises about 9px above its field
  ([ADR 0059](0059-floating-labels-and-field-errors.md)), so it nearly met the help line of the field above.
- Pairs of fields sat in a wrapping flex row with a minimum of 8rem each. On a phone the three phase fields broke
  two and one, Distance and Duration were about 150px wide with three lines of help under Duration, and "Average
  heart rate" was cut off.
- From 600px the dialog sat in the middle but kept the phone's top bar: Close, the title and Save as a small text
  button in its corner, with nothing at the end of the form.
- The plan form ran title, a four-line description, visibility, phases and goal in one column; the activity form
  gave its optional fields the weight of the needed ones.

## Decision

- A dialog's form is a grid with a 16px gap between its fields, chip groups and groups.
- Pairs of fields stack on a phone and sit side by side in equal columns from 600px, where the dialog is at most
  35rem wide; the three phase fields fit on one line there.
- From 600px the dialog is a basic dialog: its headline at the top, lined up with the fields, and Cancel and a filled
  Save at the bottom. Delete, when editing, stays at the top. On a phone it keeps the top bar. Both sets of buttons
  are drawn and CSS shows one, as for a screen's main action ([ADR 0068](0068-main-action-in-the-app-bar.md)).
- The plan form has a "Schedule" heading over the phases and goal, and its description starts at two lines. The
  activity form has an "Optional" heading over Name, Climb and Average heart rate, which no longer say "Optional"
  each.

## Consequences

- Every form dialog spaces its fields alike, and its pairs read at every width.
- On wider screens the way to finish is where the form ends. Tests that look for a Save button find two in the
  document; both submit the same form.
