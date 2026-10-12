# 0104. Repetitions of an interval workout, kept in its steps

- Status: Accepted. Warm-up, cool-down, several sets and a recovery distance: [0116](0116-interval-warm-up-sets-and-cool-down.md).
- Date: 2026-10-11
- Deciders: owner (reported that a new interval workout cannot say how many repetitions it has, and approved this fix); agent (the details below)

## Context

[0022](0022-workouts-in-a-plan.md) left intervals as one workout with notes ("3 x 10 min"), because the `steps` JSON field of
[0009](0009-data-model-and-api-rules.md) was not edited anywhere. The owner found that the form gives no way to set the number
of repetitions for a workout of kind intervals. The `steps` field has been in the schema since the first migration, but no client
reads or writes it yet.

## Options considered

1. **A structured interval block in `steps`**: repetitions, the distance and/or time of each rep, and a recovery time, shown in the
   form only for intervals. No migration, and it can grow into full step lists later through a version number.
2. **New number columns** (`reps`, `rep_distance_m`, ...): simpler to query, but needs a migration and ties the schema to one shape
   of interval workout.
3. **Full step lists** (warm-up, blocks, cool-down): what watches support, but a much bigger editor than the problem calls for.

## Decision

Option 1. For a workout of kind intervals, the form has **Repetitions** (1–100), **Recovery** (optional), **Distance per rep**
(metres) and **Time per rep**. Each rep needs a distance, a time or both. Rep and recovery times are typed as seconds (`90`) or
minutes and seconds (`1:30`): a plain number means seconds here, unlike the workout's Duration, where it means minutes. Each is at
most 60 minutes, and a rep is at most 20 km.

They are stored in `steps` as:

```json
{"v": 1, "reps": 6, "work": {"distance_m": 800, "duration_s": 170}, "recovery": {"duration_s": 90}}
```

Unset values are left out. `steps` is `null` when the workout has no repetitions, including when its kind is changed from
intervals to something else. All repetition fields can stay empty, so an interval workout described only in its notes still works.
Steps the client cannot read (another `v`, missing values) are ignored, and the workout is still shown without them.

The calendar and the workout's dialog show them as `6 × 800 m, 1:30 recovery` before the distance and duration. Copying a plan
([0028](0028-copy-a-plan.md)) now copies `steps` too.

## Consequences

- The workout's Distance and Duration stay the targets for the whole session. They are not worked out from the repetitions, so
  weekly totals and matching ([0015](0015-domain-core.md), [0089](0089-matching-tolerance-half.md)) behave as before.
- Home does not show the repetitions yet: it reads workouts without their stored-only fields.
- Recovery is a time only. A recovery distance (such as a 200 m jog), warm-up and cool-down, or several blocks need a `v: 2` and
  are left for later.
