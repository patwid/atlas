# 0018. The sync engine: a pure command/event state machine

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (implements [0004](0004-offline-first-data-and-sync.md), using [0016](0016-sync-core-outbox-and-cursor.md) and [0017](0017-session-and-http-layer.md))

## Context

The outbox and cursor rules (0016) and the request and answer handling (0017) still had to be put
together into a run: what to send when, what to do with each answer, and when to stop. This is where
the dangerous cases live, so it has to be testable without a browser or a server.

## Decision

`atlas/sync.gleam` is a pure state machine. The caller feeds it `Event`s (`Started`, `Responded`) and
executes the `Command`s it returns: `Send` a request, `SaveOutbox`, `Apply` pulled records, `Reconcile`,
`SaveCursor`, `Tell` a notice, `RetryIn` some seconds. Nothing in it touches the network or storage.

A run:

1. **Start**: refuses to run with an expired token (`SignInRequired`). Otherwise clears stale in-flight
   marks and sends `auth-refresh` as a **session check**; its answer is passed on (`SessionRefreshed`) so the
   app can store the fresh token. `401` means sign in again; no answer means retry later.
2. **Push**: outbox entries are sent one at a time (0016). An update with an unknown base first fetches
   the record's `updated`. A `400/403/404` answer is followed by another session check and is only a rejection
   if the session is valid (0017). Conflicts and rejections become notices (`Conflicts`, `Rejections`)
   and the run carries on. A network error or 5xx saves the outbox and retries with backoff.
3. **Pull**: every collection in turn, page by page, with the cursor rules (0016). `Apply` leaves out
   records that have unsent local edits. A collection the server refuses is reported (`PullFailed`) and skipped.
4. **Commit**: only after all collections are fetched is the session checked once more. If it
   is still valid, the held `Reconcile` (full resyncs only) and `SaveCursor` commands are emitted. If it is
   not, they are discarded and the user is asked to sign in. Records that were fetched with a token that went invalid
   mid-run were empty anonymous answers, so nothing derived from them (deleted records, moved cursors) may stand.
5. **Finish**: local writes made during the run are pushed before `Finished`.

`Started` is ignored while a run is going on, and answers that no longer match the current step are ignored.
The caller must call `Started` on app start, when the device comes back online, after local writes and
when a `RetryIn` timer fires.

## Consequences

- Each run costs two or three extra `auth-refresh` calls. That is cheap and buys safety against the
  anonymous-token behaviour, which would otherwise silently empty the local copy.
- Executing `Reconcile` is the caller's job: delete local records of that collection that are not in
  `keep_ids`, except those with pending outbox entries. The caller also has to turn `Conflicts` into conflicted
  copies and `Apply` into local writes (decoders per collection come with the data layer).
- A pull that fails halfway repeats from the start on the next run. Cursors of collections that
  completed are not saved until the commit step succeeds, so their pages are fetched again. It is wasteful but correct.
- 33 tests run the engine against a fake PocketBase (stale base, duplicate ID, revoked token, paging,
  broken collection, backoff). They do not replace a test against the real server once the caller exists.
