# 0102. Today first on the home screen

- Status: Accepted
- Date: 2026-10-10
- Deciders: owner (asked for today to come before Coming up, with the last seven days kept last)

## Context

[ADR 0082](0082-today-newest-first.md) put the week ahead on top, so the home screen read as one timeline from the future
down to the past, with Today in the middle. The owner wants Today at the top.

## Decision

The home screen lists Today, then Coming up, then the last seven days. Within Coming up and the last seven days the order
of ADR 0082 stays: newest day first. A day's workouts keep their order (plan, then position).

## Consequences

- What is planned for today is the first thing on the screen again.
- The screen no longer reads as a single timeline: Coming up, below Today, runs from the furthest day down to tomorrow.
