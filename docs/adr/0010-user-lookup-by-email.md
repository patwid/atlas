# 0010. Select users by exact e-mail lookup

- Status: Accepted
- Date: 2026-10-06
- Deciders: project owner (assignments must allow selecting a user), agent (mechanism)

## Context

An assignment names an athlete, and a coach grant names a coach ([0009](0009-data-model-and-api-rules.md)).
Users can only see each other through a grant, so a user has no way to find the person to select.
A searchable user directory would expose every account's name to every other account.

## Options considered

1. **Open user directory** (`users` list rule open to every signed-in user): simple, but it leaks who uses the app.
2. **Exact e-mail lookup through a hook (chosen)**: the caller must already know the address. The
   response has only `id` and `name`.
3. **Invite codes or links**: the best privacy, but a bigger flow (create, share, redeem, expire).
   It can replace this later.

## Decision

- `GET /api/atlas/users/lookup?email=...` for signed-in users returns `{id, name}` for an exact
  (case-insensitive) match, `404` when there is none, and `400` for a malformed address or one's own address.
- At most 30 lookups per user per 10 minutes (`429` after that), counted in memory, to make probing slow.
- Selecting a user for an assignment works in two steps. The athlete looks up the coach and creates a
  `coach_grants` row. After that the coach picks the athlete from the grants they hold (readable through
  `coach_grants` and `users`) when creating an assignment. Assigning to a user who has not granted
  access stays impossible: a coach must not be able to push content to arbitrary accounts.

## Consequences

- E-mail addresses can still be confirmed one at a time by a signed-in user. With sign-up closed
  (see [0009](0009-data-model-and-api-rules.md)) this is limited to invited users. Revisit if sign-up opens.
- The counter is in memory, so it resets when PocketBase restarts and is not shared between instances.
- The frontend needs a user picker (lookup box plus the list of granted athletes).
