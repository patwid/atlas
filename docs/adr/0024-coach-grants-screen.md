# 0024. Coach access: grants with names, and the Coaches screen

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: coaches can see their athletes and assign plans, as the owner asked; mechanism decided here)

## Context

A coach grant lets a coach see an athlete's activities and plans work ([0009](0009-data-model-and-api-rules.md))
and start plans for them ([0023](0023-assignments.md)). The athlete gives it, to someone they can find
by e-mail address ([0010](0010-user-lookup-by-email.md)). Screens also have to say *who* people are, offline, but the
`users` collection is not synced and can only be read for linked users.

## Decision

- **Names ride on the grant.** `coach_grants` gets `athlete_name` and `coach_name` (text, up to 200 characters; migration
  `1760000100_coach_grant_names.js`). The athlete writes both when giving access: their own name and the name the lookup
  returned. They are labels for screens, not identities: access is decided by the user IDs, and the server's rules ignore
  the names. A name can go stale if someone renames themselves; granting again refreshes it.
- **Coaches screen** (in Settings): the people who can see the user's training, each with "Remove access" (asks again;
  a soft delete, 0009), a form to add a coach, and below it the athletes the user coaches (read-only).
- **Adding a coach** is two steps: find by e-mail (the lookup of 0010, which needs a connection and says so when offline),
  then "Found <name>. Let them see your training?" with "Give access". Finding someone gives no access. Refused before
  anything is sent: an empty or incomplete address, the user's own address, and someone who already has access.
- **E-mail addresses in URLs**: `+` is encoded as `%2B`. A bare `+` in a query string is read as a space, so
  `name+tag@example.com` would not be found. (`uri.percent_encode` leaves `+` alone.)
- **Who can do what** follows the server: only the athlete creates, changes or removes a grant; the coach sees it
  (and can start plans for the athlete, 0023) until the athlete removes it, after which the grant is no longer visible to the coach
  and the coach's device drops it at its next sync.

## Consequences

- Removing access does not delete data the coach's device already has until it syncs, and it cannot erase what a
  coach has already seen. It stops further access. This should be explained in the privacy notice before launch.
- Without a reachable server there is no way to add a coach (the lookup is online-only by design), but removing one
  works offline and is queued.
- A grant made before this change has no names and shows as "Unnamed athlete" / "Unnamed coach" until it is replaced.
- The whole-app tests run the whole story with two users against a real PocketBase: the athlete looks up and adds her
  coach (a failed lookup first), the coach starts his plan for her, she finds it "Assigned by" him and can move her date but
  not restart or edit it, and removing access hides the grant from the coach.
