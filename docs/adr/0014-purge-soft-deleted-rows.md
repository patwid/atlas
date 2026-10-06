# 0014. Purge soft-deleted rows after a retention period

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (implements the retention point of [0004](0004-offline-first-data-and-sync.md))

## Context

Deletes are soft (`deleted = true`) so that devices pulling by `updated > cursor` learn about them
([0004](0004-offline-first-data-and-sync.md), [0009](0009-data-model-and-api-rules.md)). Strava
removal leaves empty tombstones too ([0012](0012-strava-integration-hooks.md)). Without a purge
the tables only grow. A purge that is too early breaks a device that was offline: it never sees the
tombstone and keeps the record.

## Decision

- A daily cron job `atlas_purge_deleted` (03:17 server time, `pb_hooks/purge.pb.js`) hard-deletes rows with
  `deleted = true` and `updated` older than the retention. Superusers can run it on demand with
  `POST /api/crons/atlas_purge_deleted`.
- **Retention is 90 days**, set by `ATLAS_PURGE_RETENTION_DAYS` (fractions allowed, used by the tests).
  A device that has been offline for longer than that must discard its local data and sync from scratch
  instead of using its cursor. The sync engine has to detect this (the server cannot tell it).
- Collections are handled children first: `matches`, `activities`, `assignments`, `workouts`,
  `plan_shares`, `plans`, `coach_grants`, in batches of 500. Only rows that are themselves
  soft-deleted and old are selected, but PocketBase's cascade deletes also remove their children,
  so live workouts, shares and assignments of a purged plan go with it.
- `strava_connections` has no soft delete and is removed directly when a user disconnects.
- Each run logs how many rows it removed per collection.

## Consequences

- The sync engine must delete the children of a deleted plan locally when it pulls the plan's
  tombstone, because their own deletions are never seen by the clients.
- The cron endpoint returns before the job has finished, so tests wait for a known row to disappear.
- Because the cursor is `updated`, a purge never changes what a current client sees.
- Revisit the 90 days if users commonly stay offline longer, or if table sizes ever make the daily scan slow.
