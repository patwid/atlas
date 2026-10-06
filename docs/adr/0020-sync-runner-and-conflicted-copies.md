# 0020. The sync runner in the app, local writes and conflicted copies

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (implements 0004 and 0011 in the app, on top of [0018](0018-sync-engine.md) and [0019](0019-device-database.md))

## Context

The engine (0018) only decides; the device database (0019) only stores. Something has to execute
the engine's commands, react to its notices, and give pages a way to write. ADR 0004 and 0011 also promise
that a conflicting edit is saved as a copy "rather than lost", which nothing implemented yet.

## Decision

- **`syncing.gleam`** is the runner, with its own state and message type embedded in the app's. It loads the
  device database after sign-in (`local.load`, which also applies the one-owner rule), executes each
  command as an effect (HTTP with the session token, writes to IndexedDB, a retry timer) and returns
  the notices the app must act on. The app handles a fresh session (stored) and "sign in again" (signed out,
  data kept); the runner handles the rest.
- **Triggers**: a run starts when the device data has loaded, when the device comes back online, after
  every local write, and when a retry timer fires. The engine ignores a start while a run is going on.
- **Local writes** (`create`, `edit`, `delete`) change the outbox, write the record into the device database
  first and then the outbox, and start a run. Before the device data is loaded they do nothing, so a
  change is never accepted and then lost. A delete is a soft delete (0009).
- **After a save** the server's answer replaces the local record, so the next edit uses the new `updated`
  as its base (otherwise it would conflict with the user's own earlier save). If further edits of that
  record are queued, the local copy is left as it is.
- **Conflicts** (`409` after `base_updated`, 0011): for plans and workouts the user's version, read from the device
  database, becomes a new record with a fresh ID and " (conflicted copy)" added to its title, queued for
  upload; the server's version of the original is fetched and stored; the user is told in Settings. For
  everything else (matches, grants, shares, activities, assignments) the server's version wins and the user is told.
  A local version that was a delete is not copied. Children are not copied: a plan's copy has no workouts.
- **Rejections**: an entry the server refuses (after the session check, 0017) is dropped. If it was a
  create, the local record is removed (the server will never have it); otherwise the server's version is fetched.
  The reason is shown.
- **Problems** are kept in the app state (newest first, at most 20) and shown in Settings until dismissed. They are
  not persisted. A write failure to the device database (storage full) is shown separately.

## Consequences

- A conflicted copy of a plan loses its workouts. The original keeps them, so nothing is lost, but the user
  has to re-create the structure in the copy. Copying children is possible later.
- A conflict resolved while the user has newer unsent edits to the same record skips fetching the server's
  version for that record; the next conflict handles it.
- The app's tests check the state transitions. The only test of the effects is `frontend/test-js/app.e2e.test.mjs`, which
  runs the built app in jsdom with fake-indexeddb against a real PocketBase: offline work is pushed, a stale edit
  becomes a conflicted copy, device and server end identical; a second user wipes the first user's data and cannot
  upload it; an expired session signs out and keeps unsent work.
- jsdom is not a real browser. Behaviour that depends on real IndexedDB eviction, tab concurrency (two tabs of the app
  would both run a sync) and service workers is untested. Two tabs should be coordinated with a Web Lock before launch.
