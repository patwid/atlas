# 0004. Offline-first: IndexedDB as the client source of truth, with an outbox synced to PocketBase

- Status: Accepted (by the owner 2026-10-06)
- Date: 2026-10-06
- Deciders: agent

## Context

The PWA must work offline, for example on a track or a trail with no signal. PocketBase has
no offline or sync support. Training plans are mostly edited by a single author, and shared
plans are read (or copied) by others. Conflicts are therefore rare, but they can happen when
the same user edits on two devices.

## Options considered

1. **Cache API responses only (network-first, cache fallback)**: simple, but nothing can be
   written while offline.
2. **Local store plus mutation outbox (chosen)**: every write goes to IndexedDB and an outbox
   queue, and the outbox is replayed against PocketBase when the device is back online.
3. **CRDT or sync framework (Automerge, PowerSync, ...)**: more than plan editing needs, and
   none integrate with PocketBase or Gleam.

## Decision

- **App shell**: the service worker precaches the built assets (cache-first, with a versioned cache
  name). API calls are never cached by the service worker. Data offline is handled by the app.
- **IDs**: records are created with client-generated PocketBase-compatible IDs (15 chars, `[a-z0-9]`),
  so a record created offline keeps its ID after sync.
- **Writes**: `update` emits an effect that writes to IndexedDB and appends `{op, collection, id, payload, base_updated}`
  to the outbox. The UI shows local state immediately.
- **Sync**: triggered on startup, on the `online` event, on Background Sync where supported,
  and after each local write while online. The outbox is replayed in order. Then each collection
  pulls records changed since the last sync (`updated > cursor`).
- **Conflicts**: last writer wins per record. A record edited while offline (its `base_updated` no
  longer matches the server) is saved as a copy ("conflicted copy") rather than lost. A
  pb_hooks guard enforces this check on the server.
- **Deletes**: soft delete (a `deleted` flag) so the pull step sees them. Purged after a retention period.
- **Strava activities** are read-only on the client and cached for offline viewing.

## Consequences

- We write and own a small sync engine. It needs thorough tests (offline create, edit and
  delete; two-device conflicts; auth expiring while offline).
- Every synced collection needs `updated` indexes and `deleted` fields, and its API rules must
  allow the pull query.
- Browser storage can be evicted. We request `navigator.storage.persist()` and warn when the
  outbox is not empty.
