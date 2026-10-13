# 0126. Count a dated plan's weeks from its start again

- Status: Accepted
- Date: 2026-10-13
- Deciders: owner (week numbers relative to the plan instead of the year); agent (the details below)

## Context

[0109](0109-plan-weeks-named-by-week-of-the-year.md) named a dated plan's weeks by their ISO week of the year
("Week 46"). The owner wants the weeks numbered relative to the plan instead: how far into the plan a week is matters
more when training than its calendar week, and the dates beside each week already place it in the year.

## Decision

- Every plan's weeks are named "Week 1", "Week 2", … from the plan's first week, with or without a start date, in the
  calendar row, the week and workout dialogs, the workout form's week list and the screen-reader labels. Phases still
  count their own weeks ("Week 6 · Pre-competition 2").
- Supersedes 0109. `date.iso_week` stays as a tested date helper.

## Consequences

- Week names always increase, also across a new year, and moving a plan's start date no longer renames its weeks.
- The calendar week of a week is no longer shown; its dates ("16–22 Nov") are.
