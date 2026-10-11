# 0105. A target zone for each workout

- Status: Accepted
- Date: 2026-10-11
- Deciders: owner (asked for a zone to be selectable in the workout editor); agent (the details below)

## Context

Athletes have heart-rate, lactate and pace zones in their settings ([0034](0034-heart-rate-zone-settings.md),
[0035](0035-lactate-zone-settings.md), [0036](0036-pace-zone-settings.md)), five of each, but nothing used them. The owner asked
for a zone to be selectable when editing a workout. A plan is written once and followed by several athletes
([0023](0023-assignments.md), [0029](0029-sharing-plans.md)), each with their own zone boundaries.

## Options considered

1. **A zone number, 1 to 5, in a new `zone` column on `workouts`**: one choice for every kind of zone, since all three have five;
   each athlete reads it against their own boundaries. Needs a migration.
2. **The zone in `steps`**: no migration, but `steps` holds the repetitions of interval workouts ([0104](0104-interval-repetitions.md))
   and is `null` for every other kind.
3. **A zone of a given kind (heart rate, pace or lactate)**: more precise, but a second choice in the form for a difference the
   numbers already share.

## Decision

Option 1. Migration `1760000800_workout_zone.js` adds `zone` to `workouts`, a whole number from 0 to 5, not required: 0 or no value
means no zone, so rows saved before and app versions that do not know it keep working. A client ignores a value it does not know.

The workout form has an optional **Zone** select ("No zone", "Zone 1" to "Zone 5") for every kind except a rest day, which never
has a zone. The calendar and the workout's dialog show it first among the targets: `Zone 4 · 6 × 800 m, 1:30 recovery · 10 km`.
For an interval workout it is the zone of the reps. Copying a plan ([0028](0028-copy-a-plan.md)) copies it.

## Consequences

- The zone is a number only: the app does not yet show the athlete's range for it (such as `152–170 bpm`), nor check activities
  against it. Both can follow, reading the athlete's zones from `athlete_settings`.
- Home does not show the zone yet, as it does not show the repetitions (0104).
- A zone per rep and per recovery, or a choice of the kind of zone, would need a later decision.
