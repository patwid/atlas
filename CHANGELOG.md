# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Design decisions live in [docs/adr](docs/adr/README.md). Entries link to the related ADR where there is one.

## [Unreleased]

### Added
- ADR process and the initial architecture decisions (ADR 0001–0006).
- Pinned toolchain (`.tool-versions`) and `scripts/install-tools.sh` for Gleam 1.19.0, Erlang/OTP 27 and PocketBase 0.40.4 (ADR 0006).
- `backend/` layout for PocketBase hooks, migrations and static files (ADR 0002, 0006).
- `sbx/default` sandbox kit that allows `repo.hex.pm` and Strava (ADR 0007).
- `flake.nix` and `flake.lock`: development shell with all tools from nixpkgs unstable (`nix develop`); the sandbox kit allows `cache.nixos.org` (ADR 0032).
- `nix build` and `nix run` for the whole app (frontend, hooks, migrations, PocketBase launcher); `build-frontend.sh` accepts `ATLAS_BUILD_ID` and `ATLAS_PUBLIC_OUT` (ADR 0033).
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
- `plan_shares` carry display names, and a plan shared with someone can be started by them (migration `1760000300_plan_share_names_and_start_rule.js`, ADR 0029).
- Share a plan with named people by e-mail address, see who shared a plan with you, and start a plan that was shared with you; stop sharing with a confirmation (ADR 0029).
- Heart-rate zones in Settings: the maximum heart rate and where each of the five zones starts, filled with defaults (50-90 % of 190 bpm) until you save your own, synced across devices and visible to your coach. New collection `athlete_settings` (migration `1760000400_athlete_settings.js`, ADR 0034).
- Lactate zones in Settings: where each of the five zones starts in mmol/L, filled with defaults (1.0, 1.5, 2.5, 4.0, 6.0) until you save your own; the section is now "Training zones" (migration `1760000500_athlete_settings_lactate_zones.js`, ADR 0035).
- Pace zones in Settings: a threshold pace and where each of the five zones starts in min/km, filled with defaults (from a 5:00 /km threshold) until you save your own, with a button to work the zones out from the threshold pace (migration `1760000600_athlete_settings_pace_zones.js`, ADR 0036).
- Coach's view: an Athletes tab for coaches, with each athlete's last six weeks (planned, done, missed, distances), the plans they follow and their latest activities, read-only (ADR 0031).
- Strava's official "Connect with Strava" button and "Powered by Strava" logo (unchanged, checked by checksum), and a "View on Strava" link on Strava activities (ADR 0027).
- GitHub Actions CI (`.github/workflows/ci.yml`): builds the Nix package and runs the Gleam, backend and frontend-JS test suites on every push and pull request (ADR 0041).
- Plan phases (base, pre-competition, competition; 4 weeks each by default), a weekly distance goal and an intensity per week (0–100%, set with a slider). The plan screen is now a calendar, weeks as rows and days as columns in bands per phase, with a sidebar for the open workout, the selected week against the goal, and the plan's settings (ADR 0043).

### Changed
- Strava's redirect now returns to `/settings?strava=<result>` (ADR 0027).
- All buttons, inputs, selects and textareas now use Shoelace web components instead of plain HTML
  elements (self-hosted, vendored under `frontend/assets/shoelace/`), except the Strava "Connect"
  button and attribution images, which keep their brand-locked native markup (ADR 0037).
- Migrated those components from Shoelace to its successor, Web Awesome (self-hosted, vendored
  under `frontend/assets/webawesome/`), following Web Awesome's own migration guide (ADR 0038).
- Every delete/remove/disconnect/unlink confirmation prompt is now a `wa-dialog` modal instead of
  an inline button swap, with focus trapping, Escape-to-cancel and a light-dismiss backdrop (ADR
  0039).
- The app now follows Material Design 3: its color roles (light and dark), type scale, shapes and state layers; filled, outlined and text buttons, outlined text fields, M3 dialogs and cards, and a navigation bar with icons that becomes a navigation rail on wide screens. Still hand-written CSS, no library (ADR 0044).
- Material Design 3's baseline colors (purple) replace the blue scheme and every custom color: intensity, workout kinds and phase bands now use M3 color roles; only Strava's brand orange remains (ADR 0045).
- Buttons follow Material Design 3's names and rules: filled, outlined and text buttons, and no red danger button. Confirmation dialogs show two text buttons, the dismissive one first (ADR 0046).
- More Material Design 3 components: snackbars for status messages (plan copied, Strava info, zones saved), floating action buttons for New plan and Add activity, segmented buttons for plan visibility, chips for workout kind and sport, lists instead of cards, and tonal buttons for secondary actions (ADR 0047).
- A back arrow in the app bar replaces the "← All plans" and "← All athletes" links; a progress bar under the app bar shows a running sync; "Checking…" and "Copying…" get a spinner; Today shows each workout's state as a colored chip (ADR 0048).
- Settings is a list whose rows open each section on its own page (`/settings/account`, `/sync`, `/zones`, `/coaches`, `/strava`); Strava's return address opens the Strava page. Being offline is a banner that explains it, and sync problems are a banner at the top of Settings (ADR 0049).
- Badges for a state or origin carry an icon (Public, Not synced yet, an activity's source); empty lists and "Page not found" are empty states with an icon and, where it helps, an action; Edit, Delete and Copy to my plans have icons (ADR 0050).
- CI builds the flake's checks (`atlas-app`, `gleam-test`, `backend-test`, `frontend-js-test`) offline instead of running the test scripts in `nix develop`; `nix flake check` runs them locally, and a suite whose source is unchanged is not run again. `test-frontend-js.sh` accepts `ATLAS_NPM_INSTALL=0` (ADR 0042).

### Fixed
- Drop-downs (day, kind, sport, visibility, athlete) open on the form's current value again instead of the first option: `field.select` marks the selected option instead of setting the `<select>`'s value before its options exist.
- The whole-app tests look for confirmation questions and buttons only in the open dialog, so they no longer press another item's closed one.
- Removing a plan share or a coach's access now also removes the data from the other person's device, by a periodic membership sweep (ADR 0030).
- An edit made right after a save is no longer refused as a conflict when the screen has not yet refreshed: the sync engine now remembers the newest `updated` it has seen per record (ADR 0026).
- E-mail addresses containing `+` are now found by the lookup (`+` is encoded in the request).
- A sync requested while another one is running is no longer lost: one more run follows (ADR 0018, addendum).
- Test servers are stopped with SIGKILL, and tests have a timeout, so a slow PocketBase shutdown can no longer keep the test process alive.
- The HTTP glue no longer reports an error thrown by the app's own handler as "no connection".

### Changed
- Coach access to athletes' activities, including Strava-sourced data, now that Strava has confirmed the usage in writing (ADR 0005).
- ADRs 0003 and 0004 accepted.
