# 0082. Today, newest first

- Status: Superseded by [0102](0102-today-first-on-home.md) (section order only)
- Date: 2026-10-09
- Deciders: owner (asked for newer events first and the week ahead on top)

## Context

[ADR 0073](0073-today-order-details-and-menu.md) ordered Today as today, the last seven days (newest first), then the
week ahead (soonest first), so that what needs doing came first. The owner wants one order through the whole screen,
newest first, with the week ahead on top.

## Decision

Today lists, newest day first: Coming up (from the furthest day of the week ahead to tomorrow), Today, then the last
seven days (from yesterday back). A day's workouts keep their order (plan, then position).

## Consequences

- The screen reads as one timeline from the future down to the past. Today is no longer at the very top: it follows
  the week ahead, and missed workouts or activities to confirm are below both.
