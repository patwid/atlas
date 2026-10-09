# 0064. A week's intensity scales its distance goal; the goal stays one per plan

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner

## Context

[ADR 0043](0043-plan-phases-goal-and-calendar.md) left two questions open: whether a week's intensity should scale
the weekly distance goal, and whether the goal should be settable per week.

## Decision

- **Intensity scales the goal**: a week's goal is the plan's weekly goal times the week's intensity, so a week at 60%
  aims for 60% of it (`plan_schedule.week_goal`). A week without an intensity aims for the full goal; a week at 0%
  has no distance goal, so no share is shown. The sidebar's distance ("16.00 km of 32.00 km (50%)") and meter use
  the week's goal, and follow the slider while it is dragged. The goal field says so in its help.
- **The goal stays one per plan**: no per-week goal. The intensity is how a week differs.

## Consequences

- Nothing new is stored: the week's goal is worked out from the plan's goal and the week's intensity.
- ADR 0043 is accepted with these answers.
