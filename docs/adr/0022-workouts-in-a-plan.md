# 0022. Workouts in a plan

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: plans are made of workouts; the owner asked for creating and sharing plans)

## Context

A plan without workouts is empty. Workouts sit on a day of the plan ([0009](0009-data-model-and-api-rules.md):
`day_index`, 0 for the first day) and get calendar dates only when an athlete starts the plan on a start date.
The screen has to let a coach build a plan quickly, including on a phone, and to show an athlete the same plan read-only.

## Decision

- **Layout**: the plan's screen shows its workouts as weeks of seven days ("Week 3", "Day 2"), not as weekdays,
  because the weekday depends on the start date of each assignment. Every day, also an empty one, has its own
  "+ Add". Each week shows its total distance and time. The weeks run to the last one that has a workout.
  This layout is a pure function (`plan_schedule`) with tests.
- **Form**: week, day, title, kind (easy, long, tempo, intervals, race, rest, cross-training, strength),
  distance, time and notes. Distance is typed in kilometres with a point or a comma (`8,5`), time as minutes
  (`45`) or clock style (`1:15`, `1:15:30`). They are stored as metres and seconds, with 0 meaning "no target".
  Limits repeat the server's, plus sensible ones (week 1-60, distance up to 1000 km, time up to 48 hours) that
  keep typing mistakes out. Parsing and validation are pure (`workout_form`).
- **Order**: a workout is added at the end of its day (`position` is one more than the highest on that day).
  Moving a workout to another day puts it at the end of the new day.
- **Writes** follow the plans screens ([0021](0021-plans-screens.md)): the screen returns `Action`s, the app performs
  them through the sync runner, edits send only changed fields with the local copy's `updated` as base, deleting asks
  twice. The data is read from the device database and re-read whenever records change.
- **Permission**: only the owner of the plan can add, edit or delete. The app tells the screen which plan is open and
  whether the user owns it; with no open plan or someone else's plan, every change is ignored. Others see the
  workouts without any buttons. (The server enforces the same rule through `plan.owner`, 0009.)
- **Stored shape**: the domain `Workout` stays small (what planning and matching need). The editing screen reads a
  `Row` that adds the notes and the local `updated`.

## Consequences

- A conflicted copy of a workout ([0020](0020-sync-runner-and-conflicted-copies.md)) appears in the same plan and day, titled
  "... (conflicted copy)".
- Deleting a plan does not delete its workouts on the server: they stay, hidden with their plan, until the plan is purged
  (cascade, 0014). The screens show workouts only through their plan.
- There is no drag-and-drop, copying of a week or reordering within a day yet; moving a workout means changing its day in the form.
- Intervals are one workout with notes ("3 x 10 min"). Structured steps (the `steps` field of 0009) are not edited yet,
  so they cannot take part in matching ([0015](0015-domain-core.md)).
- The whole-app tests drive this screen against a real PocketBase: adding with typed values (`8,5` km, `1:15`),
  adding to the same day, moving and renaming, deleting after the question, and a shared plan shown read-only.
