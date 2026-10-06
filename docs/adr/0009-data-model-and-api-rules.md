# 0009. Data model and API rules

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (within the product scope set by 0004 and 0005)

## Context

The app needs plans that can be shared, athletes who follow plans, activities from watches matched
against planned workouts, and coaches who can see their athletes' work. PocketBase API rules are the
authorization layer ([0002](0002-use-pocketbase-as-backend.md)). The sync design
([0004](0004-offline-first-data-and-sync.md)) needs client-generated IDs, an `updated` field to pull
by, and soft deletes. Strava data has to stay server-written ([0005](0005-wearable-data-integration.md)).

## Options considered

1. **Plans as calendar entries**: a workout has a date, so a plan is bound to one season. Sharing and
   reuse would mean copying and shifting dates.
2. **Plans as templates plus an assignment (chosen)**: a workout sits on `day_index` (0 = first day of
   the plan). An assignment gives a plan a start date for one athlete, so one plan can be reused
   and shared.
3. **Matching stored on the activity**: this needs update rights on Strava activities, which should
   be read-only for clients. A separate `matches` collection keeps `activities` immutable for them.

## Decision

All collections except `strava_connections` have `created`, `updated` (indexed together with the owner
column) and `deleted` (bool, soft delete). Clients cannot hard-delete (`deleteRule` is `null`); a hook
purges old deleted rows later. IDs are client-generated (default PocketBase pattern).

| Collection | Purpose | Key fields |
|---|---|---|
| `users` (built-in) | accounts | `name` |
| `coach_grants` | athlete lets a coach see their data | `athlete`, `coach` |
| `plans` | a training plan template | `owner`, `title`, `description`, `visibility` (`private` / `public`), `source_plan` (copied from) |
| `plan_shares` | plan shared with a named user (read only) | `plan`, `user` |
| `workouts` | one planned workout in a plan | `plan`, `day_index`, `position`, `title`, `kind`, `description`, `distance_m`, `duration_s`, `steps` (json) |
| `assignments` | an athlete follows a plan from a date | `plan`, `athlete`, `assigned_by`, `start_date` |
| `activities` | a recorded session | `owner`, `source` (`strava` / `fit` / `manual` / `garmin`), `external_id`, `started_at`, `sport`, metrics, `laps` (json) |
| `matches` | links an activity to a planned workout | `owner`, `activity` (unique), `assignment`, `workout` |
| `strava_connections` | Strava OAuth tokens | `user` (unique), `strava_athlete_id`, tokens, `expires_at` |

Rules:

- `strava_connections` has all rules `null`, so only hooks and superusers reach it.
- A user is a **coach of** an athlete when an undeleted `coach_grants` row has that athlete and coach.
- Plans (and their workouts) are readable by the owner, by anyone for `public` plans, by users in `plan_shares`,
  and by athletes with an assignment for them. Only the owner writes. Deleted plans are visible to the owner only.
- `assignments` are readable and creatable by the athlete and by a coach of the athlete. The creator
  has to be able to read the plan (own or public).
- `activities` are readable by the owner and by a coach of the owner. Clients may create and edit only `fit`
  and `manual` activities. `strava` and `garmin` rows are written only by hooks, matching ADR 0005,
  point 4 (Strava data is coach-visible once the athlete has granted coach access).
- `matches` are readable by the owner and a coach, and writable only by the owner, for the owner's own activity and assignment.
- Ownership and relation fields cannot be changed after creation (`:changed = false` in the update rules).
- `users` can be viewed by oneself and by users linked through `coach_grants`.

The rules are tested against a real PocketBase instance by `backend/tests/rules.test.mjs`
(run with `scripts/test-backend.sh`).

## Consequences

- Plans can be shared and reused without copying. Copying (`source_plan`) is only needed to edit someone else's plan.
- A coach sees the athlete's activities and matches but not their plans, unless the plan is shared or assigned.
- Client-side sync must send the `deleted` flag and the whole record; the `base_updated` guard from
  ADR 0004 still has to be added as a `pb_hooks` handler.
- There is no way yet to find a user to grant coach access to (users can only be viewed through a grant).
  This needs an invite flow, to be decided in its own ADR.
- Sign-up is left at PocketBase's default (closed). Opening it is a product decision for the owner.
- Revisit if plan structure needs more than `day_index` (for example repeating weeks) or if rule
  expressions get too slow on large `activities` tables.
