# 0027. The Strava section in Settings

- Status: Accepted (behaviour); Proposed (official Strava brand assets, to be added by the owner)
- Date: 2026-10-06
- Deciders: agent (behaviour); project owner for the brand assets

## Context

The server side of Strava is done ([0012](0012-strava-integration-hooks.md)): OAuth, import, webhook, disconnect. The tokens are kept where
clients cannot read them, so the app could not even tell whether the user is connected. Users need to connect, see the state, import again and
leave. Strava's API agreement ([0005](0005-wearable-data-integration.md)) asks for its brand rules to be followed: the "Connect with Strava" button
and a "Powered by Strava" attribution.

## Decision

- **Status endpoint**: `GET /api/atlas/strava/status` answers `{configured, connected}` to signed-in users, and nothing else. `configured` is
  false when the server has no credentials, so the app can say so instead of offering a button that cannot work.
- **Return address**: Strava's redirect now leads to `/settings?strava=<result>` (it was `/?strava=...`), where the result is `connected`, `denied`,
  `scope` or `taken`. The app shows the result, removes it from the address (so a reload does not repeat it) and starts a sync so that the imported
  activities arrive. This changes the redirect target of 0012; the hook and its tests were updated.
- **The section** (Settings, below Coaches):
  - not configured: says so;
  - not connected: a short explanation, the "Connect with Strava" button and "Powered by Strava";
  - connected: "Connected to Strava. New activities arrive by themselves.", "Import the last 30 days again" (reports how many were imported)
    and "Disconnect", which asks first and then tells Strava, removes the tokens and removes Strava's activities from Atlas (0012). The removals reach the
    device with the next sync.
  - Everything here needs a connection and says so when offline. Nothing is stored on the device by this section.
- **Connecting**: the app asks the server for Strava's address (the server signs a short-lived state naming the user) and sends the browser there. Only
  `http` and `https` addresses are followed, so a wrong answer can never send the browser to a `javascript:` address.
- **Brand assets (Proposed)**: the button is a plain styled text button in Strava's orange, not the official artwork. Strava's brand guidelines require its
  own button images and logo, which are downloaded from Strava and cannot be generated. They have to be added by the owner before launch (and before
  applying for more than one connected athlete, 0005).

## Consequences

- The jump to Strava's page cannot be followed in the whole-app tests (jsdom does not navigate). They check that the app asks for the address, then play
  Strava's redirect by calling the server's callback with the signed state and open the app at the address it produces. The step from "click" to "browser
  arrives at Strava" is covered by the address check only.
- Strava's own page, the real consent screen and rate limits have not been exercised: the tests use a fake Strava, and no real credentials were available.
- The activities appear a moment after connecting, when the first import and sync finish, not at the instant of the redirect.
