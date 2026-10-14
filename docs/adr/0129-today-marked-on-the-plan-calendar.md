# 0129. Today is marked on a dated plan's calendar

- Status: Accepted
- Date: 2026-10-14
- Deciders: owner (asked for today to be highlighted in the plan's calendar); agent (the details below)

## Context

A plan with a start date shows a date on every day of its calendar ([ADR 0108](0108-plan-start-date.md)), but nothing
told which of them is today, so finding where one is in a plan meant reading the dates.

## Options considered

1. **Today's date on a filled primary pill, its weekday in the primary colour (chosen)** — how calendars commonly
   mark today; small, and the same in the phone and the wide layout.
2. **A tinted background for the whole day** — louder, and it would compete with the dimmed days before the plan's
   start (ADR 0108) and the selected week's colour.

## Decision

- On a dated plan, the day whose date is the device's today gets the `today` class and `aria-current="date"`, as the
  date picker's today has. Its date is on a filled primary pill and its weekday, where shown, is in the primary colour.
- A plan without a start date has no dates, so nothing is marked.
- On a phone, today stays in the stacked days even when it has neither a workout nor the add button, so someone who
  cannot edit the plan still sees where today is (an exception to [ADR 0072](0072-phone-calendar-without-empty-days-for-viewers.md)).

## Consequences

- Today is found at a glance, and screen readers announce it as the current date.
- For a reader on a phone, a plan shows one empty day row more while today is in it.
