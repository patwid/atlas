# 0071. Planned distances in round numbers

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's suggested order); agent (the details below)

## Context

Every distance was written with two decimals (`units.format_distance_km`): "40.00 km a week", a week's row "16.00 km /
32.00 km", a workout "8.00 km · 45:00". Plans are written in round numbers, so the zeros were noise, and on the
calendar from the expanded window class the week's label column (6rem) wrapped the pair unevenly.

## Decision

- **What is planned** — a workout's distance, a week's total and goal, the plan's weekly goal — is written with at
  most one decimal and none for a whole kilometre (`units.format_planned_km`: "16 km", "8.5 km"). A week's row writes
  the pair with the unit once: "16 / 32 km".
- **What was run** — activities, on Today, Activities and an athlete's page — keeps two decimals, as a watch reports it.

## Consequences

- A planned distance that is not a multiple of 100 m is shown rounded (8.25 km as "8.3 km"); the form keeps the
  value as entered.
