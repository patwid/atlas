# 0065. Settings as one pane at every width

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to drop the Settings sidebar on larger screens)

## Context

[ADR 0060](0060-window-size-classes-and-list-detail.md) showed Settings' list and the open section side by side from
the expanded window class. With three short sections (training zones, coaches, Strava) the list took a third of the
screen for little: it is opened rarely and its rows are seen at a glance on their own page.

## Decision

Settings is a list page whose rows open a section's page, with the app bar's back button, at every width. The sync
banners stay at the top of both. The list-detail layout and the list row's selected state are removed.

## Consequences

- Settings works the same on a phone and a desktop; the section's content keeps a comfortable reading width.
- The rest of ADR 0060 (window size classes, the rail, the FAB in the rail) stands.
