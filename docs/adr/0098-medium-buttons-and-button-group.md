# 0098. Medium buttons for a screen's only action, and a button group in a plan's app bar

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked for the M3 Expressive items left out by ADR 0095); agent (the details)

## Context

M3 Expressive has five button sizes (extra small 32px to extra large 136px), toggle buttons that change shape when
selected, and a standard button group in which the pressed button widens and its neighbours narrow.
[ADR 0053](0053-material-3-expressive.md) kept every button small (40px).

## Options considered

1. **Keep every button small.** Nothing changes.
2. **Use the larger sizes and toggle buttons wherever they could go.** Atlas has no on/off action: the only
   `aria-pressed` buttons are inside the time picker ([ADR 0054](0054-material-date-and-time-pickers.md)), which
   follows the time picker's own spec. So toggle buttons would have nothing to switch.
3. **The medium size where a button is all a screen offers, and the button group for a plan's app bar actions
   (chosen).**

## Decision

- **Medium button** (`button.medium()`, `.md-button-medium`): 56px high, 24px side space, title-medium label, 24px icon,
  squaring off to the medium corner while pressed. It is used for Sign in and for an empty state's action
  (`empty.link`), such as "All plans" when a plan is missing.
- **Standard button group** (`button.group`, `.button-group`): a plan's Edit and More in the app bar. The pressed
  button widens from 40 to 46px on the fast spatial spring, and the button next to it narrows to 34px.
- **Not adopted:** toggle buttons, the extra-small, large and extra-large sizes, and the connected group beyond plan
  visibility.

## Consequences

- The sign-in page and empty states have a clearer way on. Sign in also gets a 16px gap above it, which it lacked.
- Another app bar with several icon actions can use `button.group`. The CSS only resizes icon buttons in a group.
