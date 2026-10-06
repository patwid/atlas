# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Design decisions live in [docs/adr](docs/adr/README.md). Entries link to the related ADR where there is one.

## [Unreleased]

### Added
- ADR process and the initial architecture decisions (ADR 0001–0006).
- Pinned toolchain (`.tool-versions`) and `scripts/install-tools.sh` for Gleam 1.19.0, Erlang/OTP 27 and PocketBase 0.40.4 (ADR 0006).
- `backend/` layout for PocketBase hooks, migrations and static files (ADR 0002, 0006).
- `sbx/default` sandbox kit that allows `repo.hex.pm` and Strava (ADR 0007).
- `sbxenv.yaml` to create and attach to the dev sandbox with `sbx env run` (ADR 0008).
- PocketBase migration with the data model and API rules: plans, workouts, assignments, activities, matches, coach grants and Strava connections (ADR 0009).
- `scripts/test-backend.sh` runs the API rule tests against a throwaway PocketBase (ADR 0009).
- `GET /api/atlas/users/lookup` to find a user by exact e-mail, so coaches and athletes can be selected for grants and assignments (ADR 0010).
- Server-side `base_updated` conflict guard on synced collections: stale updates get 409 (ADR 0011).
- Strava hooks: OAuth connect and callback, 30-day import, webhook for new, changed and deleted activities and for deauthorization, disconnect with data removal (ADR 0012).
- Lustre app shell: routing, page frame, offline indicator, PWA manifest and app-shell service worker, built into `backend/pb_public` by `scripts/build-frontend.sh` (ADR 0013).
- Daily purge of soft-deleted rows older than 90 days (`ATLAS_PURGE_RETENTION_DAYS`), also runnable on demand by superusers (ADR 0014).
- Pure domain core in Gleam with tests: dates, client IDs, plan scheduling, activity-to-workout matching, pace and heart-rate zones (ADR 0015).
- Pure sync core in Gleam with tests: mutation outbox with compaction, conflict and retry handling, and pull cursors (ADR 0016).
- Sign-in with PocketBase: sign-in page, stored session with refresh, sign-out in Settings, and the HTTP/API layer with response classification pinned by a contract test against the real server (ADR 0017).
- Sync engine: a pure state machine that runs a session check, pushes the outbox, pulls every collection and commits cursors only after the session is confirmed (ADR 0018).
- Device database in IndexedDB (records, outbox, cursors, one owner per device), record decoders, and `scripts/test-frontend-js.sh` for the browser glue (ADR 0019).
- Sync runner in the app: runs the engine against the device database, local writes that queue for upload, conflicted copies of plans and workouts, and a Settings section for sync status and problems. Whole-app tests with jsdom, fake-indexeddb and a real PocketBase (ADR 0020).
- Plans screens: list, create, edit and delete plans, and read plans shared with you, working offline and syncing in the background (ADR 0021).
- Workouts in a plan: weeks and days layout with weekly totals, and add, edit, move and delete for the plan's owner (read-only for others), working offline (ADR 0022).
- Start a plan on a date from its screen, change the date or remove it, with start and end shown with weekdays (ADR 0023).
- Coaches screen in Settings: add a coach by e-mail address (find, then confirm), remove access, and see the athletes you coach. Coaches can start a plan for an athlete who granted access (ADR 0024).
- `coach_grants` carries display names (migration `1760000100_coach_grant_names.js`, ADR 0024).
- Activities screen: add, change and delete activities by hand (local time converted to UTC with the right daylight-saving offset), and see Strava activities read-only (ADR 0025).
- Today screen: the workouts of the plans you follow around today with their status (to do, missed, rest day, looks done, done); confirm a suggested activity, link one by hand, or unlink (ADR 0026).
- Matching rule change: a match can be moved to another assignment of the same user (migration `1760000200_matches_relink.js`).
- Strava section in Settings: connect, see the state, import the last 30 days again and disconnect, with the "Powered by Strava" attribution (ADR 0027). `GET /api/atlas/strava/status` tells the app whether Strava is set up and connected.
- Copy a plan with its workouts into your own plans from its screen; the copy is private and remembers its source (ADR 0028).

### Changed
- Strava's redirect now returns to `/settings?strava=<result>` (ADR 0027).

### Fixed
- An edit made right after a save is no longer refused as a conflict when the screen has not yet refreshed: the sync engine now remembers the newest `updated` it has seen per record (ADR 0026).
- E-mail addresses containing `+` are now found by the lookup (`+` is encoded in the request).
- A sync requested while another one is running is no longer lost: one more run follows (ADR 0018, addendum).
- Test servers are stopped with SIGKILL, and tests have a timeout, so a slow PocketBase shutdown can no longer keep the test process alive.
- The HTTP glue no longer reports an error thrown by the app's own handler as "no connection".

### Changed
- Coach access to athletes' activities, including Strava-sourced data, now that Strava has confirmed the usage in writing (ADR 0005).
- ADRs 0003 and 0004 accepted.
