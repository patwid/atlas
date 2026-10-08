# 0044. Style the app after Material Design 3, by hand

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked to switch the design to the latest Material Design, version 3); agent (the details below)

## Context

[ADR 0040](0040-drop-web-awesome.md) dropped Web Awesome and hand-wrote `frontend/assets/app.css` with Bootstrap's
palette and class names (`.btn-primary`, `.form-control`, ...). The owner now wants the look of
[Material Design 3](https://m3.material.io) (M3), Google's current design system: tonal color roles, its type scale,
rounded shapes, state layers, and its components (common buttons, outlined text fields, dialogs, cards, a navigation
bar).

Since ADR 0040 the markup goes through a few small modules (`atlas/ui/button`, `atlas/ui/field`, `atlas/ui/dialog`,
`atlas/shell`), so a restyle touches those and `app.css` only. The whole-app tests run in jsdom, which did not get on
with custom elements in shadow DOM (ADR 0040), and the app must keep working offline from a fixed precache (ADR 0013).

## Options considered

1. **[Material Web](https://github.com/material-components/material-web) (`@material/web`)** — Google's M3 web
   components. Lit custom elements with shadow DOM: the same jsdom trouble ADR 0040 left behind, an npm bundle step the
   app build does not have (ADR 0006), and the library has been in maintenance mode since 2024.
2. **A third-party M3 CSS framework (e.g. Beer CSS)** — one vendored stylesheet, but its own class vocabulary and
   much more than the handful of components Atlas uses; ADR 0040 chose to own the CSS rather than vendor it.
3. **Hand-written M3 in `app.css` (chosen)** — M3's tokens and component measures as plain CSS on native elements,
   behind the existing `ui` modules. No dependency, native elements for the tests, nothing new to precache.

## Decision

We style the app after M3 by hand, in `app.css`, keeping ADR 0040's native elements and `<dialog>` handling.

- **Color**: the M3 color roles as `--md-sys-color-*` custom properties, for light and dark (`prefers-color-scheme`).
  The values are the tonal-spot scheme that Google's `material-color-utilities` generates from the seed `#0d6efd`, the
  blue of ADR 0040, so the app stays blue. M3 has no success or warning role, so the training intensity colors
  (ADR 0043) stay app-specific (`--intensity-*`); phase bands are tints of the primary, tertiary and error containers.
- **Type, shape, state**: M3's type scale (`title-large` app bar, `label-large` buttons, ...), shape scale (4-28px
  corners and full pills) and state layers (8% hover, 10% focus and press, as a `::before` overlay). The typeface is
  Roboto Flex or Roboto where installed, else the system font: no web font is downloaded, to keep the precache small.
- **Components**: `button.primary`/`secondary`/`danger`/`link` keep their names and now render as M3 filled, outlined,
  error-filled and text buttons (`.md-button .md-button-*`). `field.*` renders outlined text fields
  (`.md-text-field`) with the label above the field instead of a floating label, which would need a wrapper element at
  every call site. Dialogs get M3's basic dialog shape with a headline. Lists are outlined cards, panels filled
  containers.
- **Navigation**: the tab bar is an M3 navigation bar with an icon in an active indicator; on screens of 60rem and
  wider it becomes a navigation rail on the left. The icons are Material Icons paths (Apache 2.0) drawn as inline SVG
  in `atlas/shell`, so no icon font is needed offline.
- **Chrome**: `theme-color` is the surface color of each scheme, and the app icon and manifest use the new palette.
- Strava's button and logos are unchanged (ADR 0027).

## Consequences

- Restyling stays a change to `app.css` and the `ui` modules; there is still no vendored UI library to re-pin.
- The M3 look is an approximation by hand: no ripple animation, no floating labels, and no M3 slider (the native range
  input takes the primary color through `accent-color`). M3 Expressive's newer shapes and motion are left out.
- The palette can be changed in one place by regenerating the `--md-sys-color-*` values from another seed.
- Revisit if the app needs M3 components that are costly by hand (date pickers, menus, snackbars), where a library
  would pay off again.
