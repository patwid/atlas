# 0101. Serve the app shell without dates, so deploys reach installed apps

- Status: Accepted
- Date: 2026-10-10
- Deciders: agent (asked by the owner to check that an installed PWA updates after a deploy)

## Context

[0013](0013-app-shell-and-pwa-build.md) relies on the browser fetching a changed `sw.js`: the new worker brings a new cache
name and the new shell. In production the shell is served by PocketBase straight from the Nix store
([0090](0090-nixos-module.md)), where every file has the modification time 1 January 1970, the same in every build. PocketBase
sends that as `Last-Modified`, without `Cache-Control` or `ETag`, and answers `If-Modified-Since` with 304 when the date matches.

The browser checks `sw.js` for updates on every navigation, but with a conditional request: it sends the `Last-Modified` it
has. Every deploy has the same date, so the answer is always 304 Not Modified, and an installed app (or an open tab) never sees a
new worker. Reproduced in Chromium against PocketBase 0.40.4 with two builds dated 1970: after the second "deploy" the page
kept the first worker and cache, even after `registration.update()`. With the dates removed it switched to the second build on
the next launch. Safari follows the same specification (the worker script is revalidated, not refetched). A date this old also
makes `index.html`, `atlas.js` and `app.css` fresh for years under the browser's heuristic caching, so a new worker could even
precache the old files.

## Options considered

1. **Caddy drops the dates for the shell**: no `If-Modified-Since` forwarded for paths outside `/api/` and `/_/`, no
   `Last-Modified` in the response, and `Cache-Control: no-cache`. Each check fetches the file in full (a few hundred kB per
   launch at most, and the worker serves the shell from its cache anyway). Ignoring the request header also rescues apps already
   installed, whose cached `sw.js` still carries the 1970 date. Only applies where Caddy runs.
2. **Give the build output real dates** (copy it out of the store at service start, or `touch` it): needs a writable copy and
   state outside the store; dates would still not identify a build.
3. **A versioned worker URL** (`/sw.js?v=<build>` from `index.html`): `index.html` itself is subject to the same 304, so it needs
   option 1 anyway.

## Decision

Option 1, in the NixOS module's Caddy configuration. The VM test checks that `sw.js` answers a 1970 `If-Modified-Since` with
200, `Cache-Control: no-cache` and no `Last-Modified`.

## Consequences

- A deploy reaches installed apps on the next launch after the worker has been fetched: the launch that finds the new worker
  still shows the old version ([0013](0013-app-shell-and-pwa-build.md)), the one after shows the new one. An app kept in the
  background (common on iOS) only checks when it navigates or is relaunched.
- A server without Caddy (the module with `caddy.enable = false`, `nix run`) still has the problem; put a proxy with the same
  rules in front of it.
