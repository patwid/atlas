# 0016. Sync core: a pure outbox state machine and pull cursors

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (implements the client side of [0004](0004-offline-first-data-and-sync.md), [0011](0011-sync-conflict-guard.md) and [0014](0014-purge-soft-deleted-rows.md))

## Context

ADR 0004 describes a mutation outbox and cursor pulls, 0011 fixes how the server answers stale updates,
and 0014 limits how long tombstones live. The client side has to get a lot of small cases right
(offline create then delete, an edit queued behind an unacknowledged create, a lost reply, an expired
session) and is hard to test once IndexedDB and `fetch` are involved.

## Decision

The sync rules are pure Gleam in `frontend/src/atlas/`, with no I/O. The caller (a later effect
layer) does the reading, writing and HTTP, and reports what happened.

- **`outbox`** is a state machine. `record_create`, `record_update` and `record_delete` record local
  writes. `next` returns the oldest entry, and only if nothing is in flight, so sending is strictly
  serial and a create always reaches the server before the edits and children that depend on it.
  `handle_response` takes the server's answer and returns the new outbox plus an `Outcome`.
- **Compaction (unsent entries only)**: edits merge into the record's pending entry. A create followed
  by a delete cancels out and never reaches the server. Deletes are updates with `deleted: true`
  (0009), so they use the same guard.
- **In-flight entries are never changed.** An edit made while a create is being sent is queued
  behind it with an unknown base. When the create is acknowledged, its `updated` value becomes the base
  of the later entries for that record.
- **Responses**: `Saved(updated)` removes the entry. `NetworkError` keeps it and backs off (2, 4, ... up to 256
  seconds). `Unauthorized` keeps everything and asks for a new sign-in. `AlreadyExists` on a create
  (a replay) turns it into an update whose base must be looked up first (`needs_base`).
  `Conflict` (409) and `Rejected` drop all entries for that record and hand them back
  (`Conflicted` / `Failed`), so nothing disappears silently.
- **Conflicts**: on `Conflicted` the caller pulls the server's version and saves the dropped edits as a
  new record, the "conflicted copy" of ADR 0004/0011. Copying a plan's workouts is the caller's job.
- **Restart safety**: `recover` clears in-flight flags after a restart. Resending is safe, because the server answers a
  replayed create with `AlreadyExists` and accepts an identical replayed update (0011).
- **Persistence**: the outbox converts to and from JSON text for IndexedDB. Damaged data is an `Error`, not a crash.
- **Field values are stored as encoded JSON text** (`"\"abc\""`, `"12"`), built with `field_string`,
  `field_int`, `field_float`, `field_bool` and `field_null`. Merging and comparing are then plain
  dictionary operations and the request body is assembled without a JSON value type.
- **`cursor`** decides what to pull. Without a cursor, or with one older than 80 days (the server purges tombstones
  after 90, 0014), the answer is a full resync. Otherwise it is `updated >= <cursor>`. `>=` rather than `>` so that records saved in the
  same millisecond or committed slightly late are not skipped; applying a record twice is harmless.
  `advance` never moves a cursor backwards. `may_apply` keeps a pulled record from overwriting a local
  record that still has unsent edits.
- **`collection`** lists the synced collections and their PocketBase names.

## Consequences

- The behaviour is covered by 40 tests, including a replay simulation against a small fake of the server's rules
  (lost reply, stale base, queued edits). It does not replace tests against the real server and IndexedDB.
- Still to build: the effect layer (IndexedDB and HTTP FFI), decoding pulled records, applying them locally,
  deleting the children of a deleted plan when its tombstone is pulled, and copying children into a conflicted copy.
- Serial sending means one slow request blocks the queue. That is acceptable for the expected volume
  (a few writes per session) and keeps ordering simple.
- The cursor uses the device's calendar day for its age check. A clock set far back keeps an old cursor in use;
  the server's own 409 and the reconciling pull limit the damage.
