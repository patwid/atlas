# 0068. The main action in the app bar on larger screens, a FAB only on phones

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (found a FAB out of place on larger screens and chose the app bar button)

## Context

[ADR 0067](0067-fab-at-the-bottom-at-every-size.md) kept the floating action button at the bottom right at every
size. On a tablet or desktop a floating button looks out of place for a web app; a button in the header is what
people expect there.

## Decision

- Each screen describes its main action once, as a `button.Main(icon, label, message)` from its page's
  `main_action`: New plan (the plan list), Add activity (activities), Add workout (a plan's calendar, for its owner)
  and Start this plan / Start or assign (a plan's schedule). A page draws it as a FAB (`button.fab_for`); the app
  draws it as a filled button with its icon in the app bar (`button.app_bar_for`, `Frame.main_action`), before the
  page's other actions. On a plan's page it is the open tab's.
- CSS shows the FAB below the medium window class and the app bar button from it, so both cannot show at once.
- The medium app bar keeps its back button on the left and moves whatever follows it on the first row to the right.

## Consequences

- One description of each main action; its two drawings cannot disagree.
- Phones keep the FAB within thumb's reach; larger screens get a header button, as desktop web apps have.
- ADR 0067 is superseded.
