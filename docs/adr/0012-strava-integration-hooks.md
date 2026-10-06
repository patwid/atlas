# 0012. Strava integration as PocketBase hooks

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (implements point 1 of [0005](0005-wearable-data-integration.md))

## Context

ADR 0005 decided that Strava OAuth runs server-side, that tokens are kept where clients cannot
read them, and that a webhook imports activities and handles deauthorization. The client secret must
never reach the browser, and Strava limits new apps to 200 requests per 15 minutes and 2,000 per
day ([0005](0005-wearable-data-integration.md)). The sandbox can reach Strava
([0007](0007-sandbox-network-policy-as-kit.md)) but has no credentials, so the code is tested
against a fake Strava server.

## Decision

Routes in `backend/pb_hooks/strava.pb.js`, shared code in `pb_hooks/lib/strava.js`:

| Route | Who | What |
|---|---|---|
| `GET /api/atlas/strava/connect` | signed in | returns the Strava authorize URL (scope `activity:read_all`) with a signed `state` (JWT, 10 minutes, signed with the client secret) |
| `GET /api/atlas/strava/callback` | browser, from Strava | checks the state and scope, exchanges the code, stores tokens in `strava_connections`, imports the last 30 days, redirects to `/?strava=connected` (or `denied`, `scope`, `taken`) |
| `POST /api/atlas/strava/sync` | signed in | imports the last 30 days again |
| `DELETE /api/atlas/strava/connection` | signed in | calls Strava's deauthorize, deletes the tokens, scrubs the athlete's Strava activities |
| `GET /api/atlas/strava/webhook` | Strava | answers the subscription validation (`hub.verify_token`) |
| `POST /api/atlas/strava/webhook` | Strava | `activity` create/update: fetch it and its laps with the athlete's token and upsert; `delete`: scrub; `athlete` update with `authorized=false`: remove the connection and scrub |
| `POST /api/atlas/strava/subscribe` | superuser | one-time creation of the push subscription |

Details:

- **Configuration** is read from environment variables, never from the repository: `STRAVA_CLIENT_ID`,
  `STRAVA_CLIENT_SECRET`, `STRAVA_VERIFY_TOKEN`, `ATLAS_PUBLIC_URL` (the HTTPS origin used for the
  redirect URI and webhook callback), and optionally `STRAVA_SUBSCRIPTION_ID` (events from other
  subscriptions are ignored) and `STRAVA_BASE` (tests only). Without a client id and secret the
  routes answer 503.
- **Webhook events are not trusted**: Strava does not sign them. An event only triggers a fetch from
  Strava with the owner's own token, so a forged event cannot inject data. Events always get a `200`
  quickly and failures are logged, because Strava retries otherwise.
- **Activity rows** use `source = strava` and `external_id = <Strava id>`, written only by hooks
  ([0009](0009-data-model-and-api-rules.md)). The import is idempotent. The backfill stores
  summaries only (laps would cost one request per activity), laps arrive through the webhook.
  `sport_type` maps to our `sport` values; anything unknown becomes `other`.
- **Scrubbing** (disconnect, deauthorization, Strava delete events) empties the row (name, metrics,
  laps, `external_id`, start date), sets `deleted`, and soft-deletes matches pointing to it. The
  tombstone stays so that syncing clients learn about the deletion ([0004](0004-offline-first-data-and-sync.md)).
  The later purge job removes the rows.
- **Tokens** are stored in plain text in SQLite. API access is closed
  (all rules `null`), but whoever can read `pb_data` can read them. They are refreshed two minutes before expiry.
- A Strava athlete can be linked to only one user.

## Consequences

- Strava's single-athlete capacity limit (0005) applies until the app is approved. A second user
  who connects gets Strava's own error.
- The 30-day backfill and webhook fetches share Strava's rate limits. A big backfill could use up a window, so there is no longer backfill yet.
- The hooks run on goja, so handlers load shared code with `require()` and cannot use top-level
  variables. Moving to Go ([0002](0002-use-pocketbase-as-backend.md)) is still the answer if this grows (it is about 300 lines now).
- Open for the owner: create the Strava app, set the environment variables, run `subscribe` once after
  deploying behind HTTPS, and write the Strava brand attribution into the UI (0005).

## Addendum (2026-10-06)

The callback now redirects to `/settings?strava=<result>` instead of `/?strava=<result>`, and `GET /api/atlas/strava/status` was added. See [0027](0027-strava-screen.md).
