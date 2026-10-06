# 0003. Build the frontend with Gleam and Lustre (TEA) on the JavaScript target

- Status: Accepted (project requirement); Proposed (sub-decisions below)
- Date: 2026-10-06
- Deciders: project owner (stack), agent (sub-decisions)

## Context

The owner requires Gleam and Lustre. As of 2026-10, Gleam is at v1.18 and Lustre at v5.7. Lustre
follows The Elm Architecture: `init`, `update` and `view`, with side effects expressed as
`Effect` values. Lustre has no built-in support for service workers, IndexedDB or PocketBase,
so these have to be supplied.

## Decision

- **Build**: `lustre_dev_tools` for the dev server and production bundle. The output is copied to
  PocketBase `pb_public` (see [0002](0002-use-pocketbase-as-backend.md)).
- **Side effects through FFI**: browser APIs that Gleam libraries don't cover (IndexedDB,
  service worker messages, online/offline events) get small `*.ffi.mjs` files, each wrapped
  in a typed Gleam module that returns Lustre `Effect`s. FFI files hold no business logic.
- **Backend access**: through our own sync module ([0004](0004-offline-first-data-and-sync.md)),
  not directly from `update`. The sync module uses the official `pocketbase` JS SDK through FFI
  for auth-store handling and realtime.
- **Service worker**: plain JavaScript (`sw.js`), kept outside the Gleam app, limited to app-shell
  caching and Background Sync triggers. A service worker gains little from Gleam and is
  easier to debug as plain JS.
- **Domain logic** (plan structure, pace and zone calculations, matching activities to workouts)
  goes in target-independent Gleam modules so it can be unit tested with `gleeunit`.

## Consequences

- There is a small amount of JS in the project (FFI and the service worker), but it is kept thin.
- TEA makes offline state explicit: the model always reflects local state, and network
  activity is only ever an effect.
- The Gleam ecosystem is small, so we should expect to write helpers that larger ecosystems
  already have (for example, date handling and FIT parsing; see 0005).
