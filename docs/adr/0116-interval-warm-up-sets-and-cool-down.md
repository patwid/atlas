# 0116. An interval workout's warm-up, sets and cool-down, each with a zone, distance and time

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked for a configurable warm-up and cool-down, and a zone, duration and distance for the reps and the
  recovery, set independently for each set); agent (the details below)

## Context

An interval workout kept one block of repetitions in its `steps` ([0104](0104-interval-repetitions.md)): a number of
reps, the distance and time of a rep and a recovery time. Its zone was the workout's own and meant that of the reps
([0105](0105-workout-target-zone.md)). 0104 left a recovery distance, a warm-up and cool-down, and several blocks to a
`v: 2`; 0105 left a zone per rep and per recovery to a later decision. The owner asked for all of them.

## Options considered

1. **`steps` version 2: an optional warm-up and cool-down and a list of sets, each part with its own zone, distance and
   time** (chosen) — covers pyramids (sets of one rep) and the usual `2 × (4 × 400 m)`, needs no migration.
2. **A free list of steps** (warm-up, rep, recovery, rep, …) as watches store them: most general, but typing every rep
   of a 10 × 400 m one by one is what the owner did not ask for.
3. **New columns for the warm-up and cool-down**: queryable, but needs a migration, and the sets would still live in
   `steps`.

## Decision

Option 1. A workout of kind intervals is stored in `steps` as:

```json
{"v": 2,
 "warmup": {"zone": 1, "duration_s": 900},
 "sets": [{"reps": 6, "work": {"zone": 4, "distance_m": 800, "duration_s": 246},
           "recovery": {"zone": 1, "distance_m": 200, "duration_s": 90}}],
 "cooldown": {"distance_m": 2000}}
```

- Unset values, an empty warm-up, cool-down or recovery, and an empty list of sets are left out. A zone is 1 to 5.
- **Form**: for intervals, a Warm-up group, one group per set (Repetitions, then the zone, distance and time of a rep and
  of its recovery), an **Add set** button that adds a copy of the last set, a **Remove set** button on each set when
  there are several, and a Cool-down group. A new interval workout shows one empty set; empty sets are not saved.
- **Units**: a warm-up and cool-down are typed like the workout itself, in kilometres and minutes (at most 50 km and
  5 hours); reps and recoveries as before, in metres and seconds or minutes and seconds (at most 20 km and 60 minutes).
- A set needs its repetitions (1–100) and a rep with a distance, a time or both. A warm-up, cool-down or recovery with
  a zone needs a distance or a time.
- **Worked out from the zone** ([0106](0106-targets-from-the-zone-pace.md)): each part fills in its distance or time
  from its own zone's pace; a warm-up and cool-down to the minute and 100 m, a rep and recovery to the second and 10 m.
- **The workout's zone**: the workout-level Zone is not asked for an interval workout. Its `zone` is saved as the
  highest zone of its reps, so it still says what the workout is mostly about; without zones on the reps it keeps the
  one it had.
- **Totals**: read-only Total distance and Total time add up the parts that have one: the warm-up, every rep, a recovery
  after every rep except the last of the workout, and the cool-down. As in 0106 they are not saved and do not change the
  workout's Distance and Duration.
- **Calendar and dialog**: `15:00 warm-up · 6 × 800 m in 4:06 (Zone 4), 1:30 recovery · 2 km cool-down`. The
  workout's zone is not repeated before it.
- **Version 1** steps are still read, as one set whose reps have the workout's zone. A workout's steps are written as
  version 2 when its parts are next changed, and when a plan is copied.

## Consequences

- An app version from before this one ignores version 2 steps (0104): it shows such a workout without its parts, and
  does not overwrite them unless its own repetitions are changed there.
- A rest between sets that differs from the recovery between reps cannot be given; a set of one rep with its own
  recovery comes close.
- Home still does not show the parts.
