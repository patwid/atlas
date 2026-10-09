# 0070. A workout's kind in words on the calendar, and its week and day in its name

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's suggested order); agent (the details below)

## Context

On the plan calendar ([ADR 0043](0043-plan-phases-goal-and-calendar.md), [0066](0066-plan-calendar-without-a-sidebar.md))
a workout's kind was shown only by the colour of the bar at its left edge, and the colours are those of training
intensity ([ADR 0061](0061-harmonized-intensity-colours.md)): easy and long share one, tempo and intervals another.
So the kind could not be told apart for those pairs, and not at all without colour (WCAG 1.4.1, use of colour).
From the expanded window class the day names are hidden and the column heads are `aria-hidden`, so a screen reader
read a workout as just its title and targets, with no week or day.

## Options considered

1. **The kind as a small label in the card, and an accessible name with the week and day (chosen)** — text that
   needs no colour, at the cost of one short line per workout.
2. **An icon per kind** — smaller, but eight icons to learn and still no words for screen readers.
3. **A colour per kind** — more custom colours beside the intensity ones, and still colour only.

## Decision

- Each workout in the calendar shows its kind (`workout_form.kind_label`, such as "Tempo run") above its title in
  label-small, in `on-surface-variant`; the bar keeps the intensity colour.
- Its accessible name is its title, kind, week and day and targets, such as "Shake-out, Easy run, week 2, day 2,
  8.00 km · 45:00", and it says it opens a dialog (`aria-haspopup`), as the week's button does.

## Consequences

- Workouts are a line taller. A title that already names the kind repeats it; the label is small enough for that.
