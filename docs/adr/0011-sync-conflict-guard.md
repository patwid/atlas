# 0011. Refuse stale updates with a server-side `base_updated` guard

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (implements [0004](0004-offline-first-data-and-sync.md))

## Context

ADR 0004 says an update made against a record that has since changed on the server must not
silently overwrite it, and that a `pb_hooks` guard enforces this. It left open what the server does
on a mismatch and how an update that was applied but whose response was lost (a normal case for an
outbox that replays after a network error) is told apart from a real conflict.

## Options considered

1. **The server creates the "conflicted copy" itself**: the client gets a result either way, but the
   server has to invent copies of any record type (a workout copy needs its own plan, a match
   copy is meaningless), and the copy's ID is unknown to the client's outbox.
2. **Refuse with 409 and let the client keep its version (chosen)**: the client already holds the
   edit and knows what a copy means for each record type, and the server stays small.
3. **Always last-writer-wins**: simplest, but loses edits, which ADR 0004 rules out.

## Decision

- Every update by a non-superuser to `coach_grants`, `plans`, `plan_shares`, `workouts`,
  `assignments`, `activities` and `matches` must carry `base_updated`, the `updated` value of the
  record the edit was based on. Without it the answer is `400`.
- If `base_updated` differs from the stored `updated`, the update is refused with `409`
  and a field error on `base_updated`. Nothing is written. The client fetches the current
  record and saves its own version as a new record (a "conflicted copy") where that makes sense.
- Exception: if the submitted values already equal the stored ones, the request is a replay of an
  update that took effect, and it succeeds.
- Superusers (the admin UI, hooks) are not guarded. `base_updated` is not stored: PocketBase ignores unknown body fields.
- API rules run before the hook, so users without access still get `404`.
- Deletes are soft (an update with `deleted: true`), so they go through the same guard. A delete
  based on a stale record conflicts with an edit made elsewhere instead of discarding it.

## Consequences

- The sync engine must send `base_updated` for every update and handle `409` (ADR 0004 already
  lists conflict tests for it).
- Creating a record with an ID that already exists still fails with `400`. The client treats that
  as "already created" for a replayed create.
- Direct API users that do not send `base_updated` are refused. This is intended: the app is the only client.
- An edit that is stale only in an unrelated field also conflicts. Per-field merging is not attempted;
  revisit if conflicted copies become frequent.
