# Architecture Decision Records

The process is described in [0001](0001-record-architecture-decisions.md). Copy [template.md](template.md) to start a new ADR.

| #    | Decision | Status |
|------|----------|--------|
| 0001 | [Record architecture decisions as ADRs, maintained by the agent](0001-record-architecture-decisions.md) | Accepted |
| 0002 | [Use PocketBase as the backend, extended with JS hooks](0002-use-pocketbase-as-backend.md) | Accepted |
| 0003 | [Build the frontend with Gleam and Lustre (TEA)](0003-use-gleam-lustre-frontend.md) | Accepted |
| 0004 | [Offline-first: IndexedDB with an outbox synced to PocketBase](0004-offline-first-data-and-sync.md) | Accepted |
| 0005 | [Wearable data: Strava first, FIT import, Garmin deferred](0005-wearable-data-integration.md) | Accepted |
| 0006 | [Monorepo layout and pinned toolchain](0006-repository-layout-and-toolchain.md) | Accepted |
| 0007 | [Declare the dev sandbox's network access as a committed sbx kit](0007-sandbox-network-policy-as-kit.md) | Accepted |
| 0008 | [Start the dev sandbox from a committed `sbxenv.yaml`](0008-sandbox-environment-file.md) | Accepted |
| 0009 | [Data model and API rules](0009-data-model-and-api-rules.md) | Accepted |
| 0010 | [Select users by exact e-mail lookup](0010-user-lookup-by-email.md) | Accepted |
| 0011 | [Refuse stale updates with a server-side `base_updated` guard](0011-sync-conflict-guard.md) | Accepted |
| 0012 | [Strava integration as PocketBase hooks](0012-strava-integration-hooks.md) | Accepted |
| 0013 | [App shell, routing and PWA build](0013-app-shell-and-pwa-build.md) | Accepted |
| 0014 | [Purge soft-deleted rows after a retention period](0014-purge-soft-deleted-rows.md) | Accepted |
| 0015 | [Pure domain core: dates, plans, matching and units](0015-domain-core.md) | Accepted / Proposed |
| 0016 | [Sync core: a pure outbox state machine and pull cursors](0016-sync-core-outbox-and-cursor.md) | Accepted |
| 0017 | [Sessions and the HTTP layer: plain `fetch`, tokens in `localStorage`, session checks](0017-session-and-http-layer.md) | Accepted |
| 0018 | [The sync engine: a pure command/event state machine](0018-sync-engine.md) | Accepted |
| 0019 | [The device database: IndexedDB records, meta values and one owner](0019-device-database.md) | Accepted |
| 0020 | [The sync runner in the app, local writes and conflicted copies](0020-sync-runner-and-conflicted-copies.md) | Accepted |
| 0021 | [The plans screens](0021-plans-screens.md) | Accepted |
| 0022 | [Workouts in a plan](0022-workouts-in-a-plan.md) | Accepted |
| 0023 | [Starting plans: assignments](0023-assignments.md) | Accepted |
| 0024 | [Coach access: grants with names, and the Coaches screen](0024-coach-grants-screen.md) | Accepted |
| 0025 | [Entering activities by hand](0025-manual-activities.md) | Accepted |
| 0026 | [The Today screen and stored matches](0026-today-screen.md) | Accepted |
| 0027 | [The Strava section in Settings](0027-strava-screen.md) | Accepted / Proposed |
| 0028 | [Copying a plan](0028-copy-a-plan.md) | Accepted |
| 0029 | [Sharing a plan with named people](0029-sharing-plans.md) | Accepted |
