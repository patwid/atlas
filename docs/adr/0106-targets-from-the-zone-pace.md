# 0106. Work distances and times out from the target zone's pace

- Status: Accepted. An interval workout counts its parts' totals: [0130](0130-interval-workout-totals-from-its-parts.md).
- Date: 2026-10-11
- Deciders: owner (asked for the other of distance and time to be filled in from the zone, and for read-only totals of an interval workout); agent (the details below)

## Context

A workout has a target zone from 1 to 5 ([0105](0105-workout-target-zone.md)) and athletes have pace zones in their settings
([0036](0036-pace-zone-settings.md)), but the form left both the distance and the duration to be typed. The owner asked that typing
one fills in the other from the zone, and that an interval workout ([0104](0104-interval-repetitions.md)) shows the total distance and
time of its repetitions. Of the three kinds of zones only pace links a distance to a time.

## Options considered

1. **Fill in the other field from the pace of the zone in the signed-in user's pace zones, remembering which one was typed last**:
   changing the zone works the same one out again, and a stored workout keeps its values until one of them is typed.
2. **Always work the duration out from the distance**: simpler, but a typed duration would be overwritten when the zone changes.
3. **Store the pace of the zone with the workout**: fixes the numbers for every athlete of the plan, against 0105's reading of a zone
   against each athlete's own boundaries.

## Decision

Option 1, in the form only; nothing new is stored.

- **Pace**: the middle of the zone in the pace zones of the user editing the plan (their saved ones or the defaults), and the start of
  zone 5, which has no faster end. With the default zones that is 5:08 /km for zone 4.
- **When**: typing a distance fills in the duration and typing a duration fills in the distance; choosing another zone or kind works out
  again the field that was not typed last. Clearing the typed field clears the other. Nothing happens without a zone, on a rest day, while
  the typed value is not usable, or before either field has been typed since the form opened.
- **Rounding**: a workout's duration to the minute and distance to 100 m; a rep's time to the second and distance to 10 m.
- **Intervals**: the zone is that of the reps (0105), so for an interval workout it fills in the distance or time **per rep** and leaves the
  workout's own Distance and Duration as typed. Once Repetitions is filled in, read-only **Total distance** (the reps; a recovery has no
  distance) and **Total time** (the reps and the recoveries between them: `reps × time + (reps − 1) × recovery`) are shown. They are not
  saved and do not change the workout's Distance and Duration, so 0104's targets, weekly totals and matching stay as they were.

## Consequences

- The numbers depend on whoever edits the plan: a coach writing for an athlete gets the coach's paces. Showing each athlete their own range
  for the zone, as 0105 suggests, would be the place to fix that.
- Heart-rate and lactate zones are not used, as they say nothing about how far one runs in a given time.
- A worked-out value can still be changed by hand; that field then becomes the typed one.
