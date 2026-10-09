# Architecture Decision Records

The process is described in [0001](0001-record-architecture-decisions.md). Copy [template.md](template.md) to start a new ADR.

| #    | Decision | Status |
|------|----------|--------|
| 0001 | [Record architecture decisions as ADRs, maintained by the agent](0001-record-architecture-decisions.md) | Accepted |
| 0002 | [Use PocketBase as the backend, extended with JS hooks](0002-use-pocketbase-as-backend.md) | Accepted |
| 0003 | [Build the frontend with Gleam and Lustre (TEA)](0003-use-gleam-lustre-frontend.md) | Accepted |
| 0004 | [Offline-first: IndexedDB with an outbox synced to PocketBase](0004-offline-first-data-and-sync.md) | Accepted |
| 0005 | [Wearable data: Strava first, FIT import, Garmin deferred](0005-wearable-data-integration.md) | Accepted |
| 0006 | [Monorepo layout and pinned toolchain](0006-repository-layout-and-toolchain.md) | Accepted |
| 0007 | [Declare the dev sandbox's network access as a committed sbx kit](0007-sandbox-network-policy-as-kit.md) | Accepted |
| 0008 | [Start the dev sandbox from a committed `sbxenv.yaml`](0008-sandbox-environment-file.md) | Accepted |
| 0009 | [Data model and API rules](0009-data-model-and-api-rules.md) | Accepted |
| 0010 | [Select users by exact e-mail lookup](0010-user-lookup-by-email.md) | Accepted |
| 0011 | [Refuse stale updates with a server-side `base_updated` guard](0011-sync-conflict-guard.md) | Accepted |
| 0012 | [Strava integration as PocketBase hooks](0012-strava-integration-hooks.md) | Accepted |
| 0013 | [App shell, routing and PWA build](0013-app-shell-and-pwa-build.md) | Accepted |
| 0014 | [Purge soft-deleted rows after a retention period](0014-purge-soft-deleted-rows.md) | Accepted |
| 0015 | [Pure domain core: dates, plans, matching and units](0015-domain-core.md) | Accepted (zones superseded by 0034, tolerance by 0089) |
| 0016 | [Sync core: a pure outbox state machine and pull cursors](0016-sync-core-outbox-and-cursor.md) | Accepted |
| 0017 | [Sessions and the HTTP layer: plain `fetch`, tokens in `localStorage`, session checks](0017-session-and-http-layer.md) | Accepted |
| 0018 | [The sync engine: a pure command/event state machine](0018-sync-engine.md) | Accepted |
| 0019 | [The device database: IndexedDB records, meta values and one owner](0019-device-database.md) | Accepted |
| 0020 | [The sync runner in the app, local writes and conflicted copies](0020-sync-runner-and-conflicted-copies.md) | Accepted |
| 0021 | [The plans screens](0021-plans-screens.md) | Accepted |
| 0022 | [Workouts in a plan](0022-workouts-in-a-plan.md) | Superseded by 0043 (layout and form) |
| 0023 | [Starting plans: assignments](0023-assignments.md) | Accepted |
| 0024 | [Coach access: grants with names, and the Coaches screen](0024-coach-grants-screen.md) | Accepted |
| 0025 | [Entering activities by hand](0025-manual-activities.md) | Accepted |
| 0026 | [The Today screen and stored matches](0026-today-screen.md) | Accepted |
| 0027 | [The Strava section in Settings](0027-strava-screen.md) | Accepted |
| 0028 | [Copying a plan](0028-copy-a-plan.md) | Accepted |
| 0029 | [Sharing a plan with named people](0029-sharing-plans.md) | Accepted |
| 0030 | [The membership sweep: access that is taken away reaches the device](0030-membership-sweep.md) | Accepted |
| 0031 | [The coach's view of an athlete's progress](0031-coach-view-of-an-athlete.md) | Accepted |
| 0032 | [Provide the development tools through a Nix flake](0032-nix-flake-dev-shell.md) | Accepted |
| 0033 | [Build and run the app with `nix build` and `nix run`](0033-build-and-run-with-nix.md) | Accepted |
| 0034 | [Heart-rate zones as an explicit setting](0034-heart-rate-zone-settings.md) | Accepted |
| 0035 | [Lactate zones as an explicit setting](0035-lactate-zone-settings.md) | Accepted |
| 0036 | [Pace zones as an explicit setting](0036-pace-zone-settings.md) | Accepted |
| 0037 | [Adopt Shoelace web components for UI controls](0037-adopt-shoelace-web-components.md) | Superseded by 0038 |
| 0038 | [Migrate from Shoelace to Web Awesome](0038-migrate-shoelace-to-web-awesome.md) | Superseded by 0040 |
| 0039 | [Adopt Web Awesome's dialog for confirmation prompts](0039-adopt-web-awesome-dialog.md) | Superseded by 0040 |
| 0040 | [Drop Web Awesome; roll our own styling with Bootstrap's palette](0040-drop-web-awesome.md) | Accepted (palette superseded by 0044) |
| 0041 | [Run CI on GitHub Actions through the Nix flake](0041-github-actions-ci.md) | Superseded by 0042 |
| 0042 | [Run the test suites as flake checks](0042-ci-through-flake-checks.md) | Accepted |
| 0043 | [Plan phases, a weekly distance goal, week intensity and a calendar view](0043-plan-phases-goal-and-calendar.md) | Accepted (sidebar replaced by 0066) |
| 0044 | [Style the app after Material Design 3, by hand](0044-material-design-3-styling.md) | Accepted (colors superseded by 0045) |
| 0045 | [Use Material Design 3's baseline colors only](0045-material-baseline-colors.md) | Accepted (intensity changed by 0061, phase bands by 0063) |
| 0046 | [Name buttons after Material Design 3 and drop the danger button](0046-material-button-names.md) | Accepted |
| 0047 | [Use more Material Design 3 components](0047-more-material-components.md) | Accepted |
| 0048 | [Material back button, progress indicators and status chips](0048-material-navigation-progress-status.md) | Accepted |
| 0049 | [Settings as a list of pages, and banners for offline and sync problems](0049-settings-list-and-banners.md) | Accepted (partly changed by 0055) |
| 0050 | [Badges with icons, empty states and icons in buttons](0050-chips-empty-states-button-icons.md) | Accepted |
| 0051 | [Material slider and progress, a phone layout for the athlete table, calendar cards, ripple and motion](0051-material-slider-progress-motion.md) | Accepted |
| 0052 | [The plan calendar's sidebar as a bottom sheet on smaller screens](0052-calendar-bottom-sheet.md) | Superseded by 0066 |
| 0053 | [Adopt Material 3 Expressive's shapes, motion and components where they fit](0053-material-3-expressive.md) | Accepted |
| 0054 | [Material 3 date and time pickers beside the native fields](0054-material-date-and-time-pickers.md) | Accepted |
| 0055 | [Material review, quick fixes: titles, dialogs, offline, badges, loading, icons, Settings](0055-material-review-quick-fixes.md) | Accepted |
| 0056 | [Menus for item actions, and Undo instead of confirming deletes](0056-menus-and-undo.md) | Accepted |
| 0057 | [Create and edit forms in full-screen dialogs](0057-forms-in-full-screen-dialogs.md) | Accepted |
| 0058 | [The plan page: tabs, actions in the app bar, and floating action buttons](0058-plan-page-tabs-and-app-bar-actions.md) | Accepted |
| 0059 | [Floating labels, units and errors on the field they are about](0059-floating-labels-and-field-errors.md) | Accepted |
| 0060 | [Material window size classes, the FAB in the rail, and Settings as list-detail](0060-window-size-classes-and-list-detail.md) | Accepted (list-detail dropped by 0065, FAB in the rail by 0067) |
| 0061 | [Harmonized custom colours for training intensity](0061-harmonized-intensity-colours.md) | Accepted |
| 0062 | [Material review, remaining items: a choice dialog, chips, the phone calendar, the medium app bar](0062-material-review-remaining-items.md) | Accepted |
| 0063 | [One background for all phase bands](0063-one-colour-for-phase-bands.md) | Accepted |
| 0064 | [A week's intensity scales its distance goal; the goal stays one per plan](0064-intensity-scales-the-weekly-goal.md) | Accepted |
| 0065 | [Settings as one pane at every width](0065-settings-single-pane.md) | Accepted |
| 0066 | [The plan calendar without a sidebar: week and workout dialogs, settings in the plan's Edit](0066-plan-calendar-without-a-sidebar.md) | Accepted |
| 0067 | [The FAB at the bottom right of the content at every size](0067-fab-at-the-bottom-at-every-size.md) | Superseded by 0068 |
| 0068 | [The main action in the app bar on larger screens, a FAB only on phones](0068-main-action-in-the-app-bar.md) | Accepted |
| 0069 | [One section heading, whole-row links and an empty state on every list](0069-subheaders-row-links-and-empty-states.md) | Accepted |
| 0070 | [A workout's kind in words on the calendar, and its week and day in its name](0070-workout-kind-in-words-on-the-calendar.md) | Accepted |
| 0071 | [Planned distances in round numbers](0071-planned-distances-in-round-numbers.md) | Accepted |
| 0072 | [The phone calendar leaves out empty days for those who cannot edit the plan](0072-phone-calendar-without-empty-days-for-viewers.md) | Accepted |
| 0073 | [Today: the past week before the week ahead, shorter details, a menu for a confirmed link](0073-today-order-details-and-menu.md) | Accepted |
| 0074 | [Activity rows without the usual, a Duration field, and the Strava page's problems and actions](0074-activity-rows-and-strava-page.md) | Accepted |
| 0075 | [The calendar's add button, workout titles, intensity and week names](0075-calendar-add-button-titles-and-week-names.md) | Accepted |
| 0076 | [A long plan description is cut to three lines, with More](0076-long-plan-description-cut-to-three-lines.md) | Accepted |
| 0077 | [The training zones form: outlined fields, errors at their input, Save in view](0077-training-zones-form-fields-and-errors.md) | Accepted |
| 0078 | [The person finder's errors at its field, and Settings rows that say what is set](0078-finder-errors-and-settings-summaries.md) | Accepted |
| 0079 | [Roboto Flex served with the app, the badge read out, and sticky offsets from the app bar's height](0079-bundled-roboto-flex-badge-text-and-app-bar-height.md) | Accepted |
| 0080 | [A workout or activity you can change opens in its form, with Delete there](0080-open-items-in-their-form.md) | Accepted |
| 0081 | [Today: "Link activity" as a text button beside the status](0081-today-link-activity-beside-the-status.md) | Accepted |
| 0082 | [Today, newest first](0082-today-newest-first.md) | Accepted |
| 0083 | [The person finder's search as an icon button in its field](0083-person-finder-search-in-the-field.md) | Accepted |
| 0084 | [Training zones: the Calculate buttons under their field](0084-zone-calculate-buttons-under-their-field.md) | Accepted |
| 0085 | [Form dialogs: one spacing, pairs only where they fit, buttons at the bottom on wider screens](0085-form-dialog-spacing-pairs-and-buttons.md) | Accepted |
| 0086 | [Form dialogs below the screen's height, and date and time inputs drawn plainly](0086-form-dialog-height-and-date-time-inputs.md) | Accepted |
| 0087 | [Form dialogs as high as their form](0087-form-dialog-as-high-as-its-form.md) | Accepted |
| 0088 | [The Today screen is called Home](0088-today-renamed-home.md) | Accepted |
| 0089 | [Matching accepts half to one and a half times the plan](0089-matching-tolerance-half.md) | Accepted |
