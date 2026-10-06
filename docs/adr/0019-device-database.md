# 0019. The device database: IndexedDB records, meta values and one owner

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (implements the storage part of [0004](0004-offline-first-data-and-sync.md))

## Context

ADR 0004 makes IndexedDB the client's source of truth. The sync engine ([0018](0018-sync-engine.md))
emits commands such as "apply these records", "reconcile this collection" and "save the outbox".
Something has to execute them, and the rules for who owns the data on a shared device had to be decided.

## Decision

- **Two object stores** in one database (`atlas`, version 1):
  - `records`, keyed by `collection/id`, with an index on `collection`. A row holds the record exactly as
    PocketBase sent it (`data`), so a newer server can add fields without a migration. Soft-deleted
    records stay as tombstones until a full resync or reconcile removes them.
  - `meta`, key and text value: `owner` (the user ID), `outbox` (the outbox as JSON, ADR 0016) and
    `cursor:<collection>` (a cursor as JSON).
- **Browser glue** is `store.ffi.mjs`: reading and writing with callbacks, no decisions. Every call reports
  `ok = false` on failure (quota, a closed or deleted database) instead of throwing. `store.gleam` gives
  it types. Operations that belong together run in one IndexedDB transaction (a batch of records, a merge, a reconcile).
- **One owner per device database.** `local.load` opens the database for the signed-in user. If the stored
  owner is empty or a different user, everything is deleted first and the new user is recorded. Signing in
  again as the same user keeps the data and the unsent outbox (0017). Signing out does not delete data.
- **Damaged state does not overwrite itself**: an outbox that cannot be read is an error (the app does not
  sync and does not save over it); a damaged cursor only makes that collection do a full resync.
- **Reading records** (`records.gleam`) decodes the stored objects into the domain types, skipping what
  it cannot read. Numbers are read leniently, because JavaScript has no separate integer type and PocketBase
  sends `10000`, not `10000.0`. Targets stored as 0 mean "none".
- **Tests**: the browser glue runs under Node against `fake-indexeddb` (`scripts/test-frontend-js.sh`).
  The packages live in `frontend/test-js/` with their own lock file and are never part of the app
  build; `lustre_dev_tools` changes behaviour if `frontend/node_modules` exists, which is why it is not there.

## Consequences

- Records are stored as sent, so queries (all workouts of a plan) read a whole collection and filter in
  Gleam. That is fine for the expected size (hundreds of records) and avoids secondary indexes; revisit if lists get large.
- A write is not atomic with the outbox entry that describes it (two stores written by separate calls). If the
  app dies between them the record is saved without its entry, or the other way round. The sync pull repairs
  the first case; the second is repaired by the next edit. The effect layer writes the record first.
- `navigator.storage.persist()` is available through `store.request_persistence` and should be called once after sign-in.
- The glue needs `npm` (with network access) only to run its own tests.
