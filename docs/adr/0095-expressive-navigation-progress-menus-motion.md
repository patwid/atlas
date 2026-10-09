# 0095. M3 Expressive's navigation bar and rail, progress gap, menus and springs throughout

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to look into switching to Material 3 Expressive, then to go ahead with the items below);
  agent (the details)

## Context

[ADR 0053](0053-material-3-expressive.md) adopted Material 3 Expressive's shapes, springs, button shape changes,
connected button group, segmented lists, emphasized type, loading indicator and wavy meters. Comparing `app.css`
with Expressive again, the parts every page shows were still baseline M3:

- The navigation bar was 80px. Expressive's flexible navigation bar is 64px, with a 56×32px active indicator.
- The navigation rail was 80px wide. Expressive's collapsed rail is 96px.
- The indeterminate linear progress under the app bar ran its indicator straight into the track. Expressive leaves
  a gap between them.
- Menus had extra-small (4px) corners. Expressive's menus are rounder, with items inset in the container.
- 13 transitions (state layers, shadows, the app bar's and calendar's recolouring, the navigation indicator) still
  used the old `cubic-bezier(0.2, 0, 0, 1)` easing instead of the springs.

## Options considered

1. **Leave it at ADR 0053.** No work, but the navigation, the part of the app seen most, stays baseline M3.
2. **Also adopt toolbars, FAB menus, split buttons and the Expressive colour scheme.** ADR 0053's reasons for
   leaving them out still hold: Atlas has one main action per page, and the colours stay M3's baseline
   ([ADR 0045](0045-material-baseline-colors.md)).
3. **Bring the navigation, the progress, menus and the remaining transitions in line with Expressive (chosen).**

## Decision

- **Navigation bar**: 64px plus the safe area (`--nav-bar-height`), a 56×32px active indicator, and the active label
  in `secondary`. The FAB, snackbar and sticky form actions follow through `--nav-bar-height`.
- **Navigation rail**: 96px wide (`--nav-rail-width`), which the shell's padding and the snackbar's centring use.
  The expanded rail (labels beside the icons) is not adopted. It would need different markup for the item and its
  ripple, and the collapsed rail fits the four or five destinations.
- **Active indicator**: grows out from its centre on the fast spatial spring when the destination changes, drawn as
  a background that changes size, so the state layer and ripple keep their pseudo-elements.
- **Linear progress**: the indicator has a 4px gap in the app bar's colour (`--bar-background`) on each side. It
  stays flat rather than wavy, since it is only 4px high under the bar.
- **Menus**: large (16px) corners, 4px padding, and items with the medium (12px) corner, concentric with the menu.
- **Motion**: state layers, shadows and menu items use the fast effects spring, and the app bar's colour change the
  default effects spring. Only the looping indeterminate progress and the ripple keep the cubic-bezier easing, since
  a spring does not fit a loop or a press that has no end state.

## Consequences

- Phones get 16px more room for content. Medium and larger windows give 16px more to the rail.
- Expressive's exact rail and bar values are copied by hand, as in ADR 0053. Anything sized from the old 80px must
  use `--nav-bar-height` or `--nav-rail-width`.
- Still not adopted: the expanded rail, the medium flexible app bar's subtitle, button sizes other than small,
  toggle buttons, the standard button group, toolbars, FAB menus, split buttons and the Expressive colour scheme.
