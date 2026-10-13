# 0127. Workouts on the phone calendar as two-line cards, scrolled across

- Status: Accepted
- Date: 2026-10-13
- Deciders: owner (asked for two-line cards of one height, title and total distance, scrolled across, on a phone
  only); agent (the details below)

## Context

On a phone the days of a week stack ([ADR 0066](0066-plan-calendar-without-a-sidebar.md)) and a day's workouts were
stacked under each other, each with its kind ([ADR 0070](0070-workout-kind-in-words-on-the-calendar.md)), a title of
up to two lines ([ADR 0075](0075-calendar-add-button-titles-and-week-names.md)) and its targets. So a day's height
depended on how many workouts it had and how long their titles and targets were, and a week took a lot of scrolling.

## Options considered

1. **Cards of one height with two lines, side by side and scrolled across (chosen)** — every day with workouts is as
   tall as one card; the kind and targets are left to the bar's colour, the accessible name and the dialog.
2. **Cards of one height, still stacked** — even cards, but a day with three workouts is still three cards tall.
3. **Keep the cards as they are** — all the details at a glance, at the cost of an uneven, long week.

## Decision

Below the expanded window class (under 840px) only; the wide calendar stays as it was.

- A workout is a card 2.75rem tall with two lines: its title on one line, cut with an ellipsis, and its total distance
  under it, empty when it has none. The kind label and the targets are hidden; the bar keeps the kind's intensity
  colour and the accessible name still says the kind, week, day and targets (ADR 0070).
- The total distance is the workout's distance or, for an interval workout without one, that of its parts: the
  warm-up, the reps, a recovery after every rep but the workout's last, and the cool-down, as the form's Total
  distance works it out ([ADR 0106](0106-targets-from-the-zone-pace.md), [0116](0116-interval-warm-up-sets-and-cool-down.md)). It is shown
  only, not saved.
- A day's workouts sit side by side and scroll across with scroll snapping, without a scroll bar. A single workout
  fills the day's width; with more than one each takes 85%, so the next one peeks in and shows there is more.

## Consequences

- A phone shows a week in less height, and every day with workouts is as tall as any other.
- The kind in words (ADR 0070) and the targets are no longer on the card on a phone, only in its colour, its name and
  its dialog. Workouts of a day after the first are found by scrolling across, which the peeking card hints at.
