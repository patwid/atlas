# 0122. Export a workout to a watch as a FIT workout file, written in Gleam

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked for workouts to be exported to a watch, starting with a FIT workout file); agent (the details
  below)

## Context

Athletes run their planned workouts with a watch, which can guide them through the steps and their pace targets.
[0005](0005-wearable-data-integration.md) deferred Garmin's Training API, which pushes workouts to a watch, as Garmin
only accepts legal entities and has paused applications. Strava has no API for planned workouts.

A watch stores a workout as a flat list of steps, each with how it ends (a distance, a time or a lap press), a target
(such as a pace range) and an intensity (warm-up, active, recovery, cool-down), plus "repeat steps from N, x times"
steps. In a file this is a FIT workout file ([FIT protocol](https://developer.garmin.com/fit/protocol/), file type 5):
a `file_id`, a `workout` message (26) and one `workout_step` (27) per step. Garmin watches load such a file copied
over USB into `GARMIN/NewFiles`; other devices and services (Wahoo, Hammerhead, intervals.icu) import it too.

Atlas reads FIT files with its own decoder in Gleam ([0100](0100-fit-file-import.md)) and has no npm dependencies.

## Options considered

1. **A FIT workout file, written in Gleam and downloaded** (chosen): works offline, needs no account or partner, and
   is tested like the decoder. Getting it to the watch takes a cable on Garmin.
2. **Push through intervals.icu**, which syncs planned workouts to Garmin Connect and others: wireless, but a new
   external integration with per-athlete API keys. Left for a later ADR.
3. **Garmin's Training API**: the best experience, but blocked as 0005 says.
4. **Apple WorkoutKit**: needs a native iOS app.

## Decision

Option 1.

- **Where**: an **Export to watch** button in the workout's dialog (for those who see a plan) and in the bar of its
  form (for its owner), for every kind but a rest day. It exports the workout as last saved, not unsaved changes in
  the form. The file is downloaded as `<title>.fit` through a thin FFI (`file.ffi.mjs`), and nothing is uploaded.
- **Steps** (`atlas/watch_workout`, pure):
  - **Run**: one active step of its distance or time.
  - **Race**: its warm-up, the race as an active step, its cool-down ([0119](0119-race-warm-up-and-cool-down.md)).
  - **Intervals**: the warm-up; per set a rep (active) and its recovery, then a repeat step for the set's reps; the
    cool-down ([0116](0116-interval-warm-up-sets-and-cool-down.md)). As there is no recovery after the last rep of the
    workout, the last set with a recovery repeats `reps − 1` times and is followed by one more rep. Empty parts are
    left out; a set of one rep has no repeat step.
- **How a step ends**: a step has one, while a part may have a distance and a time. A run, a rep and a race end on their
  distance, as the calendar shows them; a warm-up, cool-down and recovery on their time, as they are usually run by
  the clock. A part falls back to the other value, and a run or race without either ends on a lap press.
- **Targets**: a zone gives a pace range from the pace zones of the plan's athlete ([0036](0036-pace-zone-settings.md); the
  defaults when not on the device). Zone 5 has no faster end in Atlas, so its range runs to 2:00 /km: the watch only
  warns when it is too slow. A rep at a race goal ([0118](0118-reps-at-a-race-goal-intensity.md)) gets its pace
  ±5 s/km. A part without a zone or goal has an open target. Paces go in the file as speeds in mm/s.
- **File**: `file_id` (type workout, manufacturer "development", time created), `workout` (sport running, its title
  cut to 40 bytes, the number of steps) and the steps, little-endian, with the header and file CRCs.
- **Encoder**: `atlas/fit_workout` writes the file; the decoder's message reading is opened up (`fit.read_messages`)
  so tests read the file back.

## Consequences

- Garmin users need a cable (or a computer) to load the file; on a phone the download mostly ends in the files app.
  A wireless push (option 2 or 3) is the follow-up.
- Coros, Polar, Suunto and Apple Watch do not load FIT workout files directly as far as we know, so they are not served
  yet.
- Exporting a coach's view of a workout uses the athlete's pace zones only when the coach's device holds them, which it
  does when the athlete granted access.
- Steps carry no notes or names; the watch shows the targets and the workout's title.
