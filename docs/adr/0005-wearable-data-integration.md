# 0005. Wearable data: Strava API first, FIT file import as a fallback, Garmin API deferred

- Status: Accepted (points 1–3); point 4 accepted 2026-10-06 on the owner's report that Strava confirmed the usage in writing
- Date: 2026-10-06
- Deciders: project owner (Strava first, Garmin later, coaches see athletes' activities), agent

## Context

Users want activities from their watches matched against planned workouts. Findings as of 2026-10:

- **Strava API** ([API agreement](https://www.strava.com/legal/api),
  [support note](https://support.strava.com/hc/en-us/articles/31798729397773-API-Agreement-Update-How-Data-Appears-on-3rd-Party-Apps)):
  - Strava data may only be shown to the user it belongs to, even if it is public on Strava.
  - Strava data must not be used to train AI models.
  - New apps start with a capacity of 1 athlete ("Single Player Mode"), which can be raised to 10.
    More than 10 needs Strava's review.
  - Default rate limits: 200 requests per 15 min and 2,000 per day.
  - A webhook is required to handle deauthorization.
- **Garmin Connect Developer Program**
  ([program page](https://developerportal.garmin.com/developer-programs/connect-developer-api)):
  - Only legal entities can join, not individuals.
  - New applications are reportedly paused in 2026, with no date for reopening.
  - The Training API, which pushes workouts to the watch, would be very valuable later.
- Most Garmin, Coros, Polar and Suunto users already sync to Strava automatically. Every
  major watch can also export `.fit` files.

## Decision

1. **Strava first**: OAuth handled server-side in pb_hooks. Tokens go in a `strava_connections`
   collection with no client API access. A webhook endpoint imports new activities and handles
   deauthorization. Activity summaries (and laps, if available) are stored in `activities`, which
   only the owner can read.
2. **FIT import**: users upload `.fit` files (from any watch). These can be parsed on the client,
   so they also work offline. This covers Garmin users without needing Garmin's API.
3. **Garmin API: deferred** until the owner has a legal entity and Garmin reopens applications.
   That would be a new ADR, with the Training API (workout push) as the main reason.
4. **Coaches can see their athletes' activities**, which is what the owner asked for. Every
   activity record has a `source` field (`strava` | `fit` | `manual` | later `garmin`). A coach
   can read an athlete's activities only if the athlete has granted coach access, and Strava's
   terms add a further rule:
   - Activities from `fit`, `manual`, and later `garmin` are visible to the coach in full.
   - Activities from `strava` were first kept owner-only, because Strava's API agreement says Strava Data
     may be shown only to the user it belongs to, and press coverage from 2024-11 named coaching platforms
     (Final Surge, intervals.icu) as affected. On 2026-10-06 the owner reported that Strava confirmed
     their usage in writing, so coach visibility for `strava` follows the same athlete-granted rule as
     the other sources. It stays a single policy point in the API rules.
   - Open item: the owner should file Strava's written confirmation (for example in `docs/`) and check that it
     covers coach access to the activity metrics we store. If it does not, switch the policy point back to owner-only.
   - Plans themselves (our own data) can be shared without restriction.

## Consequences

- During development we can only connect one Strava athlete until we apply for more capacity.
  Submitting for Strava's review is a milestone before launch.
- The UI must not imitate Strava's look and must follow Strava's brand rules ("Connect with Strava"
  button, "Powered by Strava" attribution).
- A FIT parser is needed. Options are a JS library through FFI (simplest) or a Gleam port. This will
  be decided when that work starts.
- Coaches get the most value from athletes who upload FIT files directly. Garmin users can do that already.
- Revisit this ADR if the Strava terms or Garmin access change, or when Strava replies about coach access.
