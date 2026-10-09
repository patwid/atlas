# 0060. Material window size classes, the FAB in the rail, and Settings as list-detail

- Status: Accepted. Settings' list-detail layout is dropped by [0065](0065-settings-single-pane.md).
- Date: 2026-10-08
- Deciders: owner (asked to go ahead with the Material review's next steps); agent (the details below)

## Context

The layout changed at widths picked one by one (48, 60, 72 and 40rem). Material Design 3 (M3) lays out by window
size classes: compact (under 600px), medium (600-839px), expanded (840-1199px) and large (1200px and up), with a
navigation bar on compact screens and a navigation rail from medium, the FAB at the top of the rail, and the
list-detail layout (a list and the opened item side by side) from expanded.

## Decision

- `app.css` uses only the class widths: 37.5rem (medium), 52.5rem (expanded) and 75rem (large).
  - The navigation rail replaces the bar from medium (was 60rem).
  - The FAB sits at the top of the rail from medium, as an icon (its label stays for screen readers, in
    `.fab-label`), and the rail's destinations move down under it; on compact screens it stays above the bar.
  - The calendar's day columns start at expanded (was 48rem); its sidebar sits beside the calendar from large and is
    a bottom sheet below it (was 72rem, [ADR 0052](0052-calendar-bottom-sheet.md)).
  - The athlete table's cards are for compact screens (was 40rem).
- **Settings is list-detail**: `/settings` and `/settings/<section>` both draw the sync banners, the list and a
  detail pane. Below expanded only one pane shows, so they are two pages as before; from expanded both show side by
  side, the list marks the open section (`aria-current`), the detail of `/settings` says to choose a section, and
  the app bar's back button is hidden because the list is there.
- Plans and activities stay single-pane: a plan's page is a calendar that needs the width, and activities have no
  detail page.

## Consequences

- Tablets in portrait get the rail and more room for content.
- On a large screen Settings no longer needs the back button to move between sections.
