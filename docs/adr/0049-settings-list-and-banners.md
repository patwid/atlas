# 0049. Settings as a list of pages, and banners for offline and sync problems

- Status: Accepted. The offline banner and the Account and Sync pages are changed by [0055](0055-material-review-quick-fixes.md).
- Date: 2026-10-08
- Deciders: owner (asked for the remaining Material Design 3 changes); agent (the details below)

## Context

Settings was one long page: account, sync, training zones, coaches and Strava, one after another. Being offline was
a small dark chip next to the page title that did not say what it meant, and sync problems were a red box with a
plain list in the middle of Settings. Material Design 3 (M3) lays out settings as a list whose rows open each
section, and uses a banner for a condition the user should know about until it is resolved.

The icons drawn so far ([ADR 0047](0047-more-material-components.md)) were typed in by hand; more are needed now.

## Options considered

1. **One page, sections as expandable list items** — no new routes, but M3 has no accordion and the page stays long.
2. **A list page with one route per section (chosen)** — `/settings` lists the sections; `/settings/account`,
   `/settings/sync`, `/settings/zones`, `/settings/coaches` and `/settings/strava` show one each, with the app bar's
   back button to the list ([ADR 0048](0048-material-navigation-progress-status.md)).

## Decision

- **Routes**: `route.SettingsPage(page)` for the five sections. The Settings tab stays highlighted on them.
- **Strava's return**: the server keeps sending the browser to `/settings?strava=<result>`
  ([ADR 0027](0027-strava-screen.md)); the app opens the Strava page for it and replaces the address with
  `/settings/strava`. Strava's status is looked up when that page opens, not when Settings opens.
- **Settings list**: one row per section with an icon, its title and a line of supporting text (the account's name
  and e-mail address, the sync state or how many changes need attention, and so on).
- **Banners** (`atlas/ui/banner`): an icon, a message and optional actions at the top of the content.
  - Offline: shown on every page instead of the chip: "Offline. Your changes are kept on this device and synced
    when you are back online."
  - Sync problems (with Dismiss) and a full device: shown at the top of every Settings page, in the error
    container color, so they are seen on the list too.
- **Icons**: `atlas/ui/icon` is generated from Google's `@material-design-icons/svg` package (0.14.15, filled style,
  Apache 2.0) rather than typed in, so each path is Google's original.

## Consequences

- Each Settings section is one tap further away, but has its own address that can be opened directly.
- Tests open the section they use (`/settings/zones`, `/settings/coaches`, `/settings/strava`).
- A new Settings section is a new `SettingsPage` value, which the compiler makes the list, routes and titles handle.
