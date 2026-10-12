# 0123. List Coming up from tomorrow on, and fix the last seven days' order

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked for Home's Coming up to be in order); agent (the details below)

## Context

[ADR 0102](0102-today-first-on-home.md) put Today at the top of Home but kept [ADR 0082](0082-today-newest-first.md)'s
newest-first order within Coming up and the last seven days. With Today on top, Coming up ran from the furthest day of
the week ahead down to tomorrow, so the next workout was at the bottom of its section, far from Today. A Material
review of the app noticed this.

The last seven days were reversed twice (in `today.sections` and again on Home), so they showed the oldest day first,
not the latest as ADR 0082 and 0102 meant.

## Decision

- Coming up runs from tomorrow to the end of the week ahead, soonest first, so the days next to Today come first.
- The last seven days run from yesterday back, as ADR 0102 meant; `today.sections` orders them, and a day's workouts
  keep their order (plan, then position).
- Today stays at the top.

## Consequences

- Home reads outward from Today: the days nearest to it come first in both sections.
- This changes the order of ADR 0102 within Coming up.
