# 0017. Sessions and the HTTP layer: plain `fetch`, tokens in `localStorage`, session checks

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (changes one sub-decision of [0003](0003-use-gleam-lustre-frontend.md))

## Context

ADR 0003 planned to use the official `pocketbase` JS SDK through FFI for the auth store and realtime.
Atlas needs only a handful of calls (sign in, refresh, list, create, update), all documented REST.
The SDK would add an npm dependency tree, a `node_modules` step to the build (`lustre_dev_tools` changes
its behaviour when `node_modules` exists), and an auth store that duplicates the one we need to own
for offline use. Realtime is not needed by the sync design (0004).

Checking the real server (`backend/tests/contract.test.mjs`) showed that **PocketBase treats an invalid
or expired token as anonymous**. A list then answers `200` with no items, and a write fails the
API rules with `400` or `404`. Without care, an expired session would look like "the server has no data"
(a full resync would empty the local copy) or like "the server rejected this edit" (the outbox would drop real work).

## Decision

- **No SDK.** The client talks to the REST API through `fetch` (`http.ffi.mjs`, no logic). Requests
  and answers are built and read by pure code (`api`, `auth`) that the contract test pins to the server's actual behaviour.
  This supersedes the SDK point of ADR 0003; the rest of that ADR stands.
- **Session**: the sign-in answer (token, user ID, name, e-mail) is kept as JSON in `localStorage`.
  An XSS bug could read it, as with the SDK's default store, so the app must avoid
  injecting HTML and ship a content security policy later. The token has the server's 14-day lifetime.
- **Refresh**: on start and when the device comes back online, a token with less than a week left (or already
  expired) is exchanged with `auth-refresh`. The refreshed account must be the same user, or the answer is ignored.
- **Offline**: a stored session keeps working offline whatever its expiry; local data stays readable and
  writes queue in the outbox. Only the server's `401` on a refresh ends the session.
- **Expired session**: the user is signed out with a message. Local data and the outbox are **not**
  deleted, so signing in again as the same user continues the sync. Signing in as a *different* user must clear
  local data first; that rule is for the IndexedDB layer to enforce.
- **Verify before concluding** (the anonymous-token problem):
  - 400 (other than a duplicate ID on create), 403 and 404 answers to outbox entries are never final. `api.classify`
    answers `CheckSession`, the sender calls `auth-refresh`, and only a valid session makes the entry `Rejected`;
    otherwise it is `Unauthorized` and nothing is dropped.
  - A pull must not run with an expired token. An empty page from a request with an invalid token is
    never applied as authoritative.
  - An unreadable `200` answer is treated as a network error, never as a save.
- **Sign-in errors** are written for people: wrong credentials, blank fields, too many attempts, no connection, server trouble.
- **Dev server**: `lustre/dev start` proxies `/api` to PocketBase on `127.0.0.1:8090`.

## Consequences

- We maintain a small amount of request code the SDK would have provided. The contract test is what
  keeps it honest on PocketBase upgrades (ADR 0002 already makes upgrades deliberate).
- No realtime. Changes from other devices arrive on the next pull. Revisit if live coach views are wanted.
- The sender still has to be written: it sequences `next`, `entry_request`, the HTTP call, the session check and
  `handle_response`, and pulls pages with `list_page` until `has_more` is false.
- Passwords are sent only to `/api/collections/users/auth-with-password` over the page's own origin and are not stored.
