# 0121. An activity has a workout's kind and fields

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked for the activity editor to offer the kinds and fields of the workout editor, without a rest
  day; the kind replaces the sport in the form, and elevation and heart rate leave it); agent (the details below)

## Context

The workout editor asks for a title, a kind (run, intervals, race, rest day; [0114](0114-one-kind-for-every-run.md)),
a zone with the distance and duration worked out from it ([0105](0105-workout-target-zone.md),
[0106](0106-targets-from-the-zone-pace.md)), the warm-up, sets and cool-down of intervals
([0116](0116-interval-warm-up-sets-and-cool-down.md)–[0120](0120-rep-target-choice-and-intensity-slider.md)), the
warm-up and cool-down of a race ([0119](0119-race-warm-up-and-cool-down.md)) and notes. The activity editor asked for
a day and start time, one of eight sports, a distance, a duration, a name, the climb and the average heart rate. The
owner wants an activity entered by hand to be described the way a workout is planned.

Activities also come from Strava and FIT files ([0012](0012-strava-integration-hooks.md), [0100](0100-fit-file-import.md)),
which can be rides, swims and the like; only runs and trail runs fulfil a workout (0114).

## Options considered

1. **The kind replaces the sport in the form; a kind, zone, steps and notes are stored with the activity** (chosen) —
   the same form fields as a workout; the sport stays in the data for imports.
2. **A Kind next to the Sport** — nothing is lost, but the form asks two overlapping questions.
3. **The kind replaces the sport everywhere** — imported rides and swims would have to become runs or go.

## Decision

Option 1.

- **Stored**: migration `1760001300_activity_kind.js` adds to `activities` an optional `kind` (`run`, `interval`,
  `race`; empty for none), a `zone` (0–5), `steps` (the JSON of a workout's, 0116 and 0119) and a `description` (at most
  5000 characters). Nothing is migrated: an activity without a kind is read as a run when its sport is a run or trail
  run, and as its sport otherwise.
- **Form**: Day and Start time, then the workout form's fields in its order: Title, Kind (**Run**, **Intervals**,
  **Race**; no rest day, as resting is not recorded), the race's warm-up, the Zone, the parts of intervals, Distance and
  Duration, the race's cool-down and Notes, typed and checked as in a workout, with the user's race goals for reps.
  The form uses the same view code (`atlas/workout_fields`).
- **Nothing is worked out** from a zone or race goal ([0106](0106-targets-from-the-zone-pace.md),
  [0118](0118-reps-at-a-race-goal-intensity.md)): an activity's distances and times were measured, and typing one must
  not overwrite the other.
- **The title stays optional**: when empty, the activity is called by its kind or sport, as before by its sport.
- **A distance or a duration is still needed.** For intervals, one left empty is the total of the parts that have it.
- **Sport**: a kind is saved with the sport `run`, or `trail_run` for an activity that was one. An activity of another
  sport (a ride from a FIT file) shows that sport as an extra Kind choice, chosen; keeping it saves no kind, zone or
  parts, and only Distance, Duration, Title and Notes are asked.
- **Climb and average heart rate** leave the form. Values already stored, from Strava or a FIT file, are kept and still
  shown in the list.
- **List**: an activity shows its kind or sport after its date, and its zone or parts below its figures, as a workout's.
- Matching (0015, 0114) does not change: it still goes by the sport.

## Consequences

- An app version from before this one does not know the new fields: it shows such an activity without them and leaves
  them as they are when it saves its own fields.
- Climb and heart rate can no longer be typed for an activity entered by hand.
- The kind of an activity does not yet decide which workout it fulfils; a race could later be matched only to a race.
