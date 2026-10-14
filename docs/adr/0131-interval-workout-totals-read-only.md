# 0131. An interval workout's distance and duration are those of its parts, read-only

- Status: Accepted
- Date: 2026-10-14
- Deciders: owner (asked for an interval workout's total distance and duration to be read-only); agent (the details below)

## Context

[0130](0130-interval-workout-totals-from-its-parts.md) counts the totals of an interval workout's parts when it has no
distance or duration of its own, but the form still offers its own Distance and Duration next to the read-only totals
of [0106](0106-targets-from-the-zone-pace.md). A typed value then wins over the parts and can disagree with them, and
the form shows two distances for one workout.

## Options considered

1. **The parts' totals are the workout's, read-only** (chosen) — one distance and one duration, always those of the parts.
2. **Keep 0130** — a typed distance or duration overrides the parts.

## Decision

Option 1.

- The workout form shows no Distance and Duration fields for an interval workout, only the read-only Total distance and
  Total time of its parts.
- Saving an interval workout writes those totals as its `distance_m` and `duration_s`, whatever was typed before its
  kind was changed, so the stored values agree with what is shown, also for older app versions.
- When read, an interval workout with parts counts their totals (`plan.with_totals`), whatever was saved before, so
  workouts saved with a typed distance count their parts without a migration. One without parts keeps its own.
- An activity's form is unchanged: its distance and duration are what was run, and a value left empty is that of the
  parts ([0121](0121-activity-kind-and-fields-of-a-workout.md)).

## Consequences

- An interval workout's distance and duration change only through its parts.
- A workout made before 0116 with a typed total longer than its reps now counts only its parts, until a warm-up or
  cool-down is added.
