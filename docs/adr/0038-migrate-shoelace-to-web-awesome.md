# 0038. Migrate from Shoelace to Web Awesome

- Status: Superseded by [0040](0040-drop-web-awesome.md)
- Date: 2026-10-07
- Deciders: project owner

## Context

[ADR 0037](0037-adopt-shoelace-web-components.md) adopted Shoelace, self-hosted, for Atlas's five
form controls (`button`, `input`, `textarea`, `select`, `option`). Shoelace's creator has since
moved the project to [Web Awesome](https://webawesome.com), published as `@awesome.me/webawesome`;
Shoelace 2.x is in maintenance only, and new work (including Font Awesome icon integration and
further component development) happens under Web Awesome. The owner wants to move onto the
actively developed library before Shoelace falls further behind, following Web Awesome's own
[migration guide](https://webawesome.com/docs/resources/migrating-from-shoelace).

Web Awesome keeps the same shape as Shoelace (framework-agnostic Lit custom elements, a
self-hostable asset bundle, CSS custom properties for theming) but changes names and some
behaviour throughout:

- Every tag gets a `wa-` prefix instead of `sl-` (`sl-button` → `wa-button`, etc.).
- Form controls fire native `input`/`change` events instead of Shoelace's own `sl-input`/
  `sl-change`.
- Design tokens move from `--sl-*` to `--wa-*`, with some renamed outright (e.g.
  `--sl-color-primary-*` → `--wa-color-brand-*`, `--sl-border-radius-medium` → `--wa-border-radius-m`)
  and `variant="primary"` → `variant="brand"`, `variant="default"` → `variant="neutral"`. A `text`
  button variant no longer exists; the equivalent is `appearance="plain"` with no `variant` set.
- Dark mode is driven by a `wa-dark`/`wa-light` class pair rather than the presence of a single
  `sl-theme-dark` class, and (unlike Shoelace's two separate `light.css`/`dark.css` theme files)
  light and dark tokens both live in one `themes/default.css`, keyed by those classes.
- `wa-input`/`wa-textarea` split `value` into two separate things: the `value` *attribute* only
  sets `defaultValue` (used for form resets), while the live, displayed value is tracked
  internally and stops reading `defaultValue` at all once the control has been assigned a value
  once (typed into, or set via the `value` *property*). This is a real behaviour change from
  Shoelace, where `value` was a single, plainly reflected property — see Decision.
- Web Awesome's published npm/jsdelivr `dist/` tree is meant for bundlers: many of its internal
  chunks `import` bare specifiers like `"lit/decorators.js"`, which only resolve with an
  import map or a bundler, unlike Shoelace's dedicated, bundler-free "cdn build". The actual
  self-contained, browser-ready build — the one the migration guide's CDN examples point at — is
  served from Font Awesome's own kit CDN, `ka-f.webawesome.com`; that one's chunks have no bare
  imports.

## Options considered

1. **Stay on Shoelace** — zero migration cost, but stays on a maintenance-only library while
   Web Awesome gets the new component work and icon integration. Rejected per the owner's request.
2. **Migrate to Web Awesome, self-hosted (chosen)** — same vendoring posture as ADR 0037 (commit
   the five components' pre-bundled files under `frontend/assets/`), onto the actively developed
   library.

## Decision

We migrate onto Web Awesome 3.14.0, keeping ADR 0037's architecture (self-hosted, five components
only, two thin Gleam interop modules, no CSS framework) and changing only what Web Awesome itself
renamed or changed behaviour for:

- **Assets**: `frontend/assets/shoelace/` is replaced by `frontend/assets/webawesome/`, vendored
  from `ka-f.webawesome.com/webawesome@3.14.0/` (the pre-bundled CDN build, not the npm `dist/`
  tree — see Context) the same way Shoelace's `cdn/` build was: each of the five components'
  entry files plus the transitive closure of the `chunks/` files they import, collected by
  following relative imports until none are left. `webawesome.css` is Atlas's own entry file,
  assembled from Web Awesome's `layers.css`, `utilities.css` and `themes/default.css` — deliberately
  *not* its `native.css`, which restyles plain `<button>`/`<input>`/`<table>`/headings globally and
  would reopen ADR 0037's choice to leave native markup (the Strava connect button in particular)
  untouched by the component library.
- **Interop**: `atlas/ui/html` and `atlas/ui/event` are updated in place (same module paths, same
  five/two functions) to the `wa-*` tags and native `input`/`change` events. `atlas/ui/html` gains
  one new function, `value`, that sets a `wa-input`/`wa-textarea`'s value as a live DOM *property*
  (`lustre/attribute.property`) rather than the `value` *attribute* (`lustre/attribute.value`):
  because of the `defaultValue` split described in Context, setting only the attribute stops
  reaching the displayed value after the control's first interaction, which would silently break
  re-rendering a `wa-input`/`wa-textarea` with a new value once the user (or an earlier render) has
  touched it — for instance reusing the same edit form's title field across different records, or
  the zones form's "fill from max/threshold" buttons refilling a field a second time. `wa-select`'s
  `value` does not have this problem (Lit still applies attribute changes to it as a property even
  though it doesn't reflect the other way), so it keeps using the plain attribute.
- **Variants**: every `sl.button`'s `variant` call site is updated: `"primary"` → `"brand"`,
  `"default"` → `"neutral"`, `"danger"` unchanged, `"text"` → `appearance="plain"` (dropping
  `variant`, since Web Awesome has no `text` variant and defaults to `neutral` already).
- **Theming**: `app.css`'s `--sl-color-primary-*` alias block (which matched Shoelace's "primary"
  color to the app's own teal `--accent`) is dropped rather than ported: Web Awesome's components
  use its stock default theme and palette (a blue `--wa-color-brand-*`) unmodified, everywhere.
  `--accent` itself is untouched and still colors the app's own native chrome (the tab bar, focus
  rings, etc.), so it and Web Awesome's brand blue are now two independent colors rather than one
  color surfaced through two token systems.
- **Dark mode toggle**: `gleam.toml`'s inline script now toggles both `wa-dark` and `wa-light` on
  `<html>` (Web Awesome's theme CSS matches on either class being present, not just the dark one's
  absence/presence the way Shoelace's `.sl-theme-dark` did).

## Consequences

- The app now tracks an actively developed library instead of a maintenance-only one, and picks up
  Web Awesome's own continued component work and Font Awesome icon integration for free if Atlas
  ever needs it.
- `attribute.autofocus` remains unusable on `wa-input` for the same reason it was on `sl-input`
  (Lustre focuses a freshly mounted element before the custom element's own first render
  completes); the two forms that already avoided it (`plans_page`, `workouts_page`) need no change.
- Vendoring moved from jsdelivr's npm-package `dist/` tree to `ka-f.webawesome.com`'s pre-bundled
  CDN build; re-vendoring on a future version bump needs to pull from the latter; pulling from the
  former would silently ship chunks with unresolvable bare `lit` imports.
- As with ADR 0037, vendored assets are re-pinned by hand on upgrade; adding a sixth component
  means vendoring its entry file and any new chunks alongside the existing ones.
