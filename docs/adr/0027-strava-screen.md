# 0027. The Strava section in Settings

- Status: Accepted
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

## Addendum: the official artwork is in (2026-10-06)

The owner downloaded Strava's packages ("1.1 Connect with Strava Buttons" and "1.2 Strava API Logos") from
[developers.strava.com/guidelines](https://developers.strava.com/guidelines/). The brand part that was `Proposed` above is done:

- **Only two files are kept**, unchanged, in `frontend/assets/strava/`: `btn_strava_connect_with_orange.svg` (237 x 48, the button) and
  `api_logo_pwrdBy_strava_horiz_orange.svg` (the "Powered by Strava" logo). The SVGs contain only paths and a rectangle (checked: no scripts, links or
  embedded images). The orange versions suit both our light and dark themes. A test pins their SHA-256 checksums to the downloaded originals, so
  an edit or an automatic "optimisation" fails; Strava's rule is never to modify, alter or animate the logos. The zip files themselves are git-ignored.
- **The Connect button** is Strava's image inside a button with none of our styling (no background, border or padding), at its own size, and
  it still leads to `strava.com/oauth/authorize` through the server's signed address. Its accessible name comes from the image's `alt` text.
- **"Powered by Strava"** is Strava's logo, small (15 px high) and apart from our own name, shown with the Connect button and the connected state.
- **"View on Strava"** (a rule that was not implemented before): wherever a Strava activity is listed (the Activities screen and the coach's view of an
  athlete), a link with exactly that text goes to `https://www.strava.com/activities/<id>`, styled bold, underlined and in `#FC5200` as the
  rules allow, opening in a new tab with `noopener noreferrer`. The ID comes from the activity's `external_id` and is only used if it is all digits,
  so nothing else can end up in the address.
- Not done: the Today screen shows a matched Strava activity as a one-line summary without the link, and we do not use the white button or the
  stacked logos. If Strava's review asks for the link there too, it is a small addition.
