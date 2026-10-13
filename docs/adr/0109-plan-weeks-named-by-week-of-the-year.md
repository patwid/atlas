# 0109. Name a dated plan's weeks by their week of the year

- Status: Superseded by [0126](0126-plan-weeks-counted-from-the-plans-start.md)
- Date: 2026-10-11
- Deciders: owner (calendar week numbers instead of 1 to n in the plan view); agent (ISO 8601 weeks, the details below)

## Context

Since [0108](0108-plan-start-date.md) every week of a dated plan is a real Monday-to-Sunday week, but the calendar
still counted them from 1 ("Week 3 · 16–22 Nov"). Coaches and athletes plan a season by calendar week, so the owner
asked for the week of the year instead.

## Options considered

1. **ISO 8601 weeks (chosen)** — weeks start on Monday, like the plan's calendar, and week 1 is the one with the
   year's first Thursday. This is the week number used in Switzerland and most of Europe, and a week of the plan is
   always exactly one ISO week.
2. **US weeks (Sunday start, week 1 holds 1 January)** — would not line up with the plan's Monday-to-Sunday rows.

## Decision

- A dated plan's week shows the ISO week of its Monday: "Week 46", in the calendar row, the week and workout dialogs,
  the workout form's week list and the screen-reader labels. Phases still count their own weeks ("Week 46 · Base 2").
- A plan without a start date keeps counting from 1, as it has no calendar weeks.
- Only the name changes: inside the app and in the data a week is still the plan's week from 1 (`day_index`, the
  keys of `week_intensity`, the form's week value).

## Consequences

- Weeks across a new year go 52, 53, 1, so the names are not always increasing; the dates beside them make the order
  clear.
- Moving a plan's start date renames its weeks.
