# 0118. A rep can be run at an intensity of a race goal

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked to choose a race goal with an intensity from 0 to 100 % in an interval workout, and to have
  the distance and time worked out and shown); agent (the details below)

## Context

An athlete's race goals ([0115](0115-race-goals.md)) are a distance and a time, so each has a pace. Interval reps are
often written against one ("6 × 1 km at 10 km pace", "400 m at 95 % of 5 km pace"), but a rep could only be given a
zone ([0116](0116-interval-warm-up-sets-and-cool-down.md)), whose distance or time is worked out from the zone's pace
([0106](0106-targets-from-the-zone-pace.md)).

## Options considered

1. **A race goal and an intensity on each rep, instead of its zone, kept in `steps` with the goal's distance and time**
   (chosen) — no migration; the pace still reads when the goal changes, is deleted, or is not on the device.
2. **Only the goal's ID in `steps`** — smaller, but a deleted goal leaves a rep with no pace, and the calendar would need
   the goals to describe the rep.
3. **One goal for the whole interval workout** — simpler form, but a workout often mixes paces (5 km and 10 km pace).

## Decision

Option 1.

- **Form**: each set's rep gets a **Rep race goal** select (the goals of the plan's athlete, `10 km in 40:00`) and, once
  a goal is chosen, a **Rep intensity** in percent, starting at 100. The select is shown only when the athlete has goals
  or the rep already has one. Choosing a goal clears the rep's zone, and choosing a zone clears the goal. Warm-up,
  cool-down and recoveries keep zones only.
- **Intensity** is a share of the goal's **speed**, a whole number from 1 to 100: the pace is `goal pace × 100 /
  intensity`, so 10 km in 40:00 (4:00 /km) at 90 % is 4:27 /km. 0 % gives no pace and is not accepted.
- **Worked out** as for a zone (0106): typing the rep's distance fills in its time and the other way round, to the
  second and 10 m; changing the goal or intensity works out again the field not typed last. The totals add them up.
- **Whose goals**: the athlete of the plan ([0110](0110-one-athlete-per-plan.md)), so a coach plans against the athlete's
  goals; their devices already hold them (0115).
- **Stored** in the rep of a version 2 `steps`:
  `"work": {"distance_m": 400, "duration_s": 101, "goal": {"id": "…", "distance_m": 10000, "time_s": 2400, "intensity": 95}}`.
  The goal's distance and time are those when the workout was saved. When the form opens, a goal that still exists is
  read as it is now (saving then stores the new values); one that is gone stays selectable as saved.
- **Calendar and dialog**: `6 × 400 m in 1:41 (95 % of 10 km pace)`, `(10 km pace)` at 100 %.

## Consequences

- A rep's saved distance and time do not follow later changes to the goal until the workout is edited again.
- App versions from before this one read such a rep without its goal and drop it if they rewrite the steps.
- A copy of a plan for another athlete ([0028](0028-copy-a-plan.md)) keeps the first athlete's goal as saved.
