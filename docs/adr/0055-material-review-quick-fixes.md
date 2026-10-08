# 0055. Material review, quick fixes: titles, dialogs, offline, badges, loading, icons, Settings

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked for a review of the app against Material Design 3 and for its quick fixes); agent (the
  review and the details below)

## Context

A review of the whole app against Material Design 3 (M3) found places where the app followed M3's look but not its
patterns. This ADR covers the small ones; the larger ones (a plan page with tabs and a FAB, full-screen dialogs for
forms, menus, floating labels, M3 window size classes and list-detail layouts) are left for later decisions.

## Decision

- **One title**: the app bar carries the page's title, and the content no longer repeats it ("Your activities",
  "Training zones", "Strava", "Athletes you coach"). On a plan's or an athlete's page the app bar shows the plan's
  or athlete's name instead of "Plan" or "Athlete". The plan list's "Your plans" and "Shared with you" stay as list
  subheaders. `atlas/shell` takes a `Frame` record with the title and the rest of what it shows.
- **Dialogs**: a short headline ("Delete workout?"), a sentence on what happens ("It is removed from this plan."),
  and actions named by what they do ("Cancel", "Delete", "Disconnect"), as M3 asks, instead of yes/no wording
  ("Yes, delete it", "Keep it"). `dialog.view` takes the supporting sentence. Today's "Yes, that is it" is "Confirm".
- **Offline** (replaces ADR 0049's banner): a cloud-off icon at the end of the app bar while offline, and a snackbar
  when the connection drops or returns ("You are offline. Your changes are kept…", "Back online…"). Pressing the
  icon shows the explanation again. These snackbars have no action and close after 6 seconds; each has a number, so
  an older timer cannot close a newer message.
- **Sync problems**: a badge with their number on the Settings tab (M3's navigation badge), so they are seen from
  any page; the banner on Settings stays.
- **Loading**: every "Loading…" uses the loading indicator (ADR 0053), not plain text.
- **Icons**: the outlined style, M3's default; the selected navigation item's icon is filled. `icon.view` draws
  outlined and `icon.filled` filled, both from Google's package.
- **Settings** (changes ADR 0049): the account (with Sign out) and the sync state are rows of the Settings list
  instead of pages of their own, which held a line each. `/settings/account` and `/settings/sync` are gone; zones,
  coaches and Strava keep their pages.

## Consequences

- Tests find a plan's name in the app bar (`.bar h1`) and the dialogs by their new wording.
- Being offline no longer takes room on every page; the explanation is a press on the icon away.
