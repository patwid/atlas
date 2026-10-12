# 0119. A race has a warm-up and a cool-down, kept in its steps

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked for a warm-up and cool-down on a race); agent (the details below)

## Context

Since [0116](0116-interval-warm-up-sets-and-cool-down.md) an interval workout has an optional warm-up and cool-down,
each with its own zone, distance and time, kept in its `steps`. A race is usually run with a warm-up before it and a
cool-down after it as well, but a race had only its own zone, distance and duration ([0105](0105-workout-target-zone.md)).

## Options considered

1. **The warm-up and cool-down of a race in `steps` version 2, without sets** (chosen) — the same format, decoder,
   form fields and summary as an interval workout; no migration.
2. **New columns for the warm-up and cool-down** — rejected in 0116 for the same reasons.
3. **Write them in the notes** — nothing is worked out from the zone and the calendar does not show them.

## Decision

Option 1.

- **Stored** as `{"v": 2, "warmup": {…}, "cooldown": {…}}` in the race's `steps`, with no `sets`; `null` when both are
  empty. Sets typed before the kind was changed to race are not saved.
- **Form**: for a race, a **Warm-up** group before the race's own Zone, Distance and Duration and a **Cool-down** group
  after them, typed, checked and worked out from their zones as in 0116.
- **The race's own** zone, distance and duration stay as they are (0105, [0106](0106-targets-from-the-zone-pace.md)): the
  warm-up and cool-down are not added to them, and no totals are shown.
- **Calendar and dialog**: `20:00 warm-up (Zone 1) · Zone 5 · 10 km · 2 km cool-down`.

## Consequences

- An app version from before this one shows a race's warm-up and cool-down in place of its zone, and drops them
  whenever it saves the race.
- A race's distance and duration in the weekly totals do not include its warm-up and cool-down, as for an interval
  workout's parts.
