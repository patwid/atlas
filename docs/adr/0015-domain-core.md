# 0015. Pure domain core: dates, plans, matching and units

- Status: Accepted (structure); Proposed (heart-rate zone method, matching tolerance)
- Date: 2026-10-06
- Deciders: agent (structure); project owner to review the Proposed points

## Context

ADR 0003 puts domain logic in target-independent Gleam modules with `gleeunit` tests, and notes that
the Gleam ecosystem is small, so date handling has to be written here. The sync layer and the UI
both need the same answers to: which day is a workout on, did an activity fulfil it, how fast was a run.

## Decision

All modules are in `frontend/src/atlas/`, have no side effects and no browser or PocketBase access.

- **`date`**: calendar dates (`YYYY-MM-DD`) with day arithmetic (Hinnant's civil-date algorithms),
  weekday, start of week (Monday) and `local_date(utc_timestamp, utc_offset_minutes)`. No time zone
  database: the caller passes the athlete's current UTC offset. This is enough for matching, but
  an activity from before a daylight-saving change could land on the wrong day if the offset is
  taken from "now"; the sync layer should store the offset with the activity when it knows it.
- **`id`**: 15 characters of `[a-z0-9]` from an injected random function (ADR 0004).
- **`plan`**: `Workout`, `Assignment`, `Scheduled`; `schedule` places a plan's workouts on calendar days from
  the assignment's start date in a stable order (date, position, ID); weekly totals; plan length.
- **`activity`**: `Activity`, `Source` and `Sport`, with conversions to and from the stored strings.
- **`matching`**: `propose(scheduled, activities, existing, offset)` and `status(...)`.
  - An activity can match a workout when it happened on the workout's local day, its sport fits the kind
    (running sports for easy/long/tempo/interval/race, strength for strength, rides, swims, hikes,
    walks and other for cross-training, nothing for rest days), and it is not wildly off the target.
  - Each activity and each workout (per assignment) is used at most once. The closest pairs are
    chosen first, with ties broken by IDs, so the result does not depend on input order.
  - Existing (confirmed or manual) matches are never changed or reused.
  - **Proposed tolerance**: the relative difference to the planned distance (or the duration, when there is
    no distance target) must be at most 1.0, so anything from nothing up to double the planned size matches.
    A workout without a target matches any compatible activity of that day.
  - `status` is `Done`, `Planned`, `Missed` or `RestDay`.
- **`units`**: pace, duration and distance formatting, and heart-rate zones.
  - **Proposed zones**: five zones as 50-60, 60-70, 70-80, 80-90 and 90-100 percent of the maximum heart
    rate. Athletes who use other schemes (heart-rate reserve, lactate threshold) need a setting later.

## Consequences

- Matching only proposes: the UI or sync layer decides whether to store a proposal as a `matches` row, and a
  user's manual match always wins.
- The modules take plain values, so the data layer has to decode PocketBase records into them
  (the decoders come with the data layer).
- Workout steps (`steps` JSON in ADR 0009) are not modelled yet, so interval structure does not take part in matching.
- Changing zone percentages or the matching tolerance is a one-line change plus tests, so the Proposed points are cheap to revisit.

## Addendum: matching takes an offset function (2026-10-06)

`matching.propose` now takes `offset_at: fn(String) -> Int`, the UTC offset in minutes at a UTC timestamp, instead of one
number. This removes the limitation described above: an activity on the other side of a daylight-saving change from "today"
is placed on its correct local day. The browser supplies the function (`clock.utc_offset_at_utc`, [0025](0025-manual-activities.md)). Tests
cover a run at 22:30 UTC on the day Swiss summer time starts, which is on the 30th locally but on the 29th with a fixed winter offset.

## Addendum: heart-rate zones are a setting (2026-10-06)

The Proposed zone method is replaced by [0034](0034-heart-rate-zone-settings.md): the zones are stored per athlete and changeable, with these
percentages as the defaults. The zone code moved from `units` to `hr_zones`.
