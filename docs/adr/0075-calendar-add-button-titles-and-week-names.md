# 0075. The calendar's add button, workout titles, intensity and week names

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's other items); agent (the details below)

## Context

From the layout review of the plan calendar ([ADR 0066](0066-plan-calendar-without-a-sidebar.md)):

- A day's add button was a text "+" about 28px tall, and from the expanded window class at 40% opacity until its day
  was hovered, so on a touch tablet it stayed faint.
- Workout titles broke anywhere (`overflow-wrap: anywhere`), mid-word in the narrow columns between 840 and 1200px.
- A week's intensity chip said only "50%", next to "16 / 32 km", where it could be read as progress.
- The calendar numbers weeks 1 to n, but the workout form's Week select and the dialogs said "Pre-competition, week 2".
- In the week dialog, someone who cannot edit the plan got a `label` and an `output` for a slider that is not there.

## Decision

- The add button is an icon button with the Add icon, 40px on a phone and 32px in the wide calendar's cells. It is
  faint until hovered only where the device can hover (`(hover: hover)`); on touch screens it is always in full.
- Workout titles wrap between words with hyphenation and are clamped to two lines; the workout's dialog has the rest.
- The intensity chip reads "Intensity 50%" to screen readers (a visually hidden word, the `visually-hidden` class) and
  as a tooltip; it still shows "50%".
- `plan_schedule.week_label` is "Week 6 · Pre-competition 2", starting with the calendar's number, in the form, the
  workout dialog and as the week dialog's headline.
- The week dialog's intensity heading is plain text for those who cannot edit.
- The workout form's Notes error says "notes", not "description".

## Consequences

- A cell's add button takes more room on a phone, where only the owner sees it
  ([ADR 0072](0072-phone-calendar-without-empty-days-for-viewers.md)).
