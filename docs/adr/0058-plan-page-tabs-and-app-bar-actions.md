# 0058. The plan page: tabs, actions in the app bar, and floating action buttons

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked to go ahead with the Material review's next steps); agent (the details below)

## Context

A plan's page stacked four sections in one long scroll: the plan (with Edit, Delete and Copy as buttons in the
content), "Workouts" (the calendar, with an "Add workout" button in its header), "Schedule" (with "Start this plan")
and "Sharing". In Material Design 3 (M3) a screen's actions sit in its top app bar, a screen's sections are tabs,
and a section's main action is a floating action button (FAB).

## Decision

- **App bar**: on a plan's page the app bar shows the plan's name ([ADR 0055](0055-material-review-quick-fixes.md))
  and its actions (`plans_page.app_bar_actions`, passed to `atlas/shell` as `Frame.actions`): for the owner, Edit and
  a menu with Make a copy and Delete; for anyone else, Copy to my plans. Copying is not offered again while a copy
  is being made or has just been made. The content keeps the description, the badges, who shared it, and the copy's
  progress and result.
- **Tabs** (`atlas/ui/tabs`, M3 primary tabs): Calendar, Schedule and, for the owner, Sharing, under the app bar and
  sticky with it. Every panel is drawn and the others are `hidden` (the ARIA tabs pattern), so each keeps its state.
  The arrow keys, Home and End move between tabs and choose them. The tab is kept in `plans_page.Model.tab`; opening
  another plan shows its calendar.
- **FABs**: "Add workout" on the calendar and "Start this plan" / "Start or assign" on the schedule; the sections'
  own headings go, since the tabs name them.

## Consequences

- The page's parts are one tap away instead of a scroll away, and the calendar has the screen to itself.
- Edit and Copy are icon buttons, found by their labels ("Edit plan", "Copy to my plans") in tests and by screen
  readers.
- Only the FAB of the tab on show is visible: the others are in hidden panels.
