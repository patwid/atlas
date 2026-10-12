# 0114. One kind for every run; no tempo, cross-training or strength workouts

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (combine easy and long runs into "run", drop tempo, cross-training and strength, and make every
  dropped or combined kind a run); agent (the migration, the hook and the reading of old kinds)

## Context

A workout had one of eight kinds (ADR 0022): easy, long, tempo, intervals, race, rest, cross-training and strength.
The owner wants fewer: easy and long runs are both just a run, and tempo runs, cross-training and strength are not
planned in Atlas. Every workout of a dropped or combined kind is to become a run.

Atlas is offline-first (ADR 0004): devices keep their own copy of each workout, may have changes queued in the outbox
with the old kinds, and an installed app may run an older version until it updates (ADR 0103). The server refuses
an update whose `base_updated` is stale (ADR 0011).

## Options considered

1. **Change the rows in SQL, keep `updated`, read old kinds as a run, and save old kinds sent as a run (chosen)** —
   no device has to pull every workout again, and no change made offline turns into a conflicted copy. A device's
   copy keeps its old kind until the workout is next changed, which the app does not notice.
2. **Change the rows through PocketBase, which moves `updated`** — every device pulls the new kinds, but a workout
   changed offline meanwhile is refused as a conflict and kept as a conflicted copy.
3. **Keep the old kinds allowed on the server** — nothing to migrate, but the server would go on accepting kinds the
   app no longer has.

## Decision

- A workout's kind is one of `run`, `interval`, `race` and `rest` (`plan.Kind`: `Run`, `Interval`, `Race`, `Rest`),
  shown as "Run", "Intervals", "Race" and "Rest day". A new workout is a run.
- Migration `1760001100_workout_kind_run.js` sets `easy`, `long`, `tempo`, `cross` and `strength` to `run` in SQL,
  without moving `updated`, and allows only the four kinds. Going back makes every run an easy run.
- The app reads the old kinds as a run (`plan.kind_from_string`).
- `pb_hooks/workout_kind.pb.js` saves an old kind sent by a user as `run`, for queued changes and apps not yet
  updated. Superusers save what they send.
- A run, intervals and a race are fulfilled by a run or a trail run (ADR 0015). Rides, swims, hikes, walks, other
  activities and strength sessions no longer match any workout.
- A run's bar on the calendar has the low intensity colour (ADR 0070), intervals the medium one.

## Consequences

- Which runs were easy, long or tempo, and which workouts were cross-training or strength, is lost; the title and
  description still say it.
- Activities that were linked to a cross-training or strength workout stay linked; new ones are no longer proposed.
- The hook can go once no app older than this version can still be installed.
