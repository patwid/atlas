# 0002. Use PocketBase as the backend, extended with JS hooks

- Status: Accepted
- Date: 2026-10-06
- Deciders: project owner (PocketBase; JS hooks confirmed 2026-10-06), agent

## Context

The owner requires PocketBase. As of 2026-10 the current release is v0.40.x, still below 1.0,
so breaking changes between minor versions are possible. PocketBase provides auth (including
OAuth2 login), collections with per-record API rules, realtime subscriptions, file storage,
and SQLite, all in one binary.

The backend also has to do things clients must not do: the Strava OAuth token exchange and
refresh (needs the client secret), a public webhook endpoint, and background imports.
PocketBase can be extended in two ways:

1. **JS hooks (`pb_hooks/*.pb.js`)**: run inside the stock binary on the embedded goja VM.
   No build step. Synchronous and ES5-ish, with no npm packages.
2. **Go framework mode**: PocketBase used as a Go library. Full language, typed, testable,
   but needs a Go toolchain and adds a third language next to Gleam and JS.

## Decision

We will use PocketBase pinned to a specific minor version, with server-side logic in
`pb_hooks` JS and the schema in `pb_migrations`, which are committed. Schema changes are never made only in the admin UI. We will switch to Go framework mode, through a new ADR, if hook
logic grows beyond about 1–2k lines or needs concurrency or libraries the JSVM lacks.

## Consequences

- The deployment is one binary plus the `pb_data`, `pb_hooks`, `pb_migrations` and `pb_public` folders.
  The built Lustre app is served from `pb_public`, so it is same-origin and needs no CORS setup.
- PocketBase API rules are the authorization layer, so every collection needs explicit rules
  and tests for them.
- Upgrading PocketBase is a deliberate step: read the changelog, then run the migration tests.
