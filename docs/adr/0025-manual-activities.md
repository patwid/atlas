# 0025. Entering activities by hand

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: the owner asked for manual entry first, before Strava and file import)

## Context

Activities are what planned workouts are matched against ([0015](0015-domain-core.md)). Strava import needs credentials
and a registered app ([0012](0012-strava-integration-hooks.md)), and FIT import needs a parser, so the first way in is typing
an activity. The server accepts client-made activities of the sources `manual` and `fit` only, and the user's
own ([0009](0009-data-model-and-api-rules.md)).

## Decision

- **Screen**: Activities lists the user's own activities, newest first, each with its local date and time, sport, distance,
  time, pace (for running, walking and hiking sports), climb and average heart rate, and a badge for where it came from
  ("Added by hand", "Strava", "From a file"). Activities of athletes the user coaches are on the device but are not listed here.
- **Add and change**: a form with day, start time, sport, an optional name, distance (`8,5` km), time (`45` minutes or `1:05`),
  and optional climb and average heart rate. A distance or a time is required, or both. Limits repeat the server's, plus
  sensible ones (distance up to 1000 km, time up to 48 hours, heart rate 30-250, years 2000-2100). Changing sends only what
  changed. Deleting asks again and is a soft delete.
- **Only manual and file activities of one's own can be changed.** Strava and Garmin activities are shown without buttons:
  they come from the provider and are rewritten at every sync ([0005](0005-wearable-data-integration.md), [0012](0012-strava-integration-hooks.md)).
- **Time zones**: people enter local time, activities are stored as UTC timestamps. The conversion uses the UTC offset
  that applies *on that date and time on the user's device* (daylight saving included), asked from the browser at the
  moment of saving, and the same is done in reverse for display and editing. The conversion code is pure
  (`date.utc_timestamp`, `date.local_datetime`) and tested across offsets and day boundaries; the browser supplies the offsets as functions.
- **Same pattern** as the other screens ([0021](0021-plans-screens.md)): own state, writes returned as `Action`s, pure form logic
  (`activity_form`).

## Consequences

- Matching ([0015](0015-domain-core.md)) still takes a single UTC offset for all activities, which is wrong for activities on the other
  side of a daylight-saving change from the offset used. Now that activities are displayed with per-date offsets, matching should
  take the same function. This is the known limitation recorded in 0015 and is the next thing to change when the Today screen uses matching.
- A manual activity has no `external_id`, so nothing stops entering the same run twice. A duplicate warning could compare start time and distance.
- The whole-app test checks the stored UTC time against the browser's own rules and was run under UTC, Europe/Zurich and
  America/New_York to catch conversions that only work in one zone.
