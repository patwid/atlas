# 0117. An interval workout has no zone of its own

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked to drop the workout-level zone of an interval workout or leave it empty); agent (the details below)

## Context

Since [0116](0116-interval-warm-up-sets-and-cool-down.md) every part of an interval workout (warm-up, each set's reps and
recovery, cool-down) has its own zone, and the form no longer asks for the workout's. 0116 still saved the workout's
`zone` ([0105](0105-workout-target-zone.md)) as the highest zone of its reps. That repeats what the parts say, can
disagree with them once they change, and the calendar does not show it for such a workout anyway.

## Options considered

1. **Save no zone (0) for an interval workout** (chosen) — the column stays for runs and races, and 0 already means "no
   zone" (0105), so no migration and no change for older app versions.
2. **Drop the `zone` column** — runs and races still need it.
3. **Keep the highest zone of the reps (0116)** — what this replaces.

## Decision

Option 1. An interval workout is saved with `zone` 0, whatever was chosen before its kind was changed, as for a rest
day. Steps of the first version (0104) take their reps' zone from the workout's (0116): when an edit clears that zone,
the steps are written again, in the second version, so the reps keep it.

## Consequences

- Only the parts of an interval workout say how hard it is. Anything that later reads a workout's zone (such as an
  athlete's range for it, 0105) has to read the parts for intervals.
- An interval workout saved with only a zone and notes, no parts, loses that zone when it is next saved.
