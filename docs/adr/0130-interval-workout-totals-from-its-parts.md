# 0130. An interval workout without a distance or duration of its own counts those of its parts

- Status: Accepted
- Date: 2026-10-14
- Deciders: owner (asked that an interval workout's total distance and duration be worked out and count towards the
  weekly goal); agent (the details below)

## Context

Since [0116](0116-interval-warm-up-sets-and-cool-down.md) every part of an interval workout has its own zone, distance
and time, and since [0117](0117-no-zone-of-its-own-for-an-interval-workout.md) the workout has no zone of its own. Its
own Distance and Duration are only filled in from a zone ([0106](0106-targets-from-the-zone-pace.md)), so they now stay
empty unless typed. 0106 shows the parts' totals in the form but does not save them or count them, so an interval
workout added nothing to its week's distance and duration, the plan's weekly goal ([0064](0064-intensity-scales-the-weekly-goal.md))
or the athlete's progress, and was matched to an activity without a target.

## Options considered

1. **Work the totals out from the parts when the workout is read** (chosen) — one function used wherever workouts are
   counted; stays right when the parts change and needs no migration, so workouts saved before this count too.
2. **Save the totals as the workout's distance and duration** — the saved value goes stale once the parts change and
   it is loaded back into the form as if typed; existing workouts would need a migration.
3. **Leave it as 0106 has it** — what the owner asked to change.

## Decision

Option 1. An interval workout without a distance of its own has that of all its parts: the warm-up, the reps, a
recovery after every rep but the last of the workout, and the cool-down; the same for its duration. A distance or
duration typed for the workout itself is kept. Nothing new is saved: the form still saves what is typed.

The planned workout (`workout_form.planned`) is what the plan calendar's week totals and goal, Home, an athlete's
progress and matching read, and what the calendar and the workout's dialog show. Only interval workouts: a race's
warm-up and cool-down are not the race's distance.

## Consequences

- This replaces 0106's "They are not saved and do not change the workout's Distance and Duration, so … weekly totals
  and matching stay as they were" for intervals: their totals now count, though they are still not saved.
- An interval workout is now matched against the distance of its parts, warm-up and cool-down included.
- A typed distance and the parts' duration can both be counted for one workout, even if they do not agree.
