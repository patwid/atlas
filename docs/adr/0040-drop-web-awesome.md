# 0040. Drop Web Awesome; roll our own styling with Bootstrap's palette

- Status: Accepted
- Date: 2026-10-07
- Deciders: project owner

## Context

[ADR 0037](0037-adopt-shoelace-web-components.md)/[0038](0038-migrate-shoelace-to-web-awesome.md)/
[0039](0039-adopt-web-awesome-dialog.md) adopted, then migrated onto, Web Awesome for Atlas's six
form/dialog components (`button`, `input`, `textarea`, `select`, `option`, `dialog`), behind two
thin Gleam interop modules (`atlas/ui/html`, `atlas/ui/event`). The owner now wants to drop the
dependency entirely: hand-roll the styling instead, using Bootstrap's color palette and class
naming conventions (`.btn`, `.btn-primary`, `.form-control`, ...) without depending on Bootstrap's
CSS or JS.

Two things made this more than a mechanical revert of ADR 0038:

- `lustre/event` already ships `on_input`/`on_change` with the exact `target.value` decoder
  `atlas/ui/event` reimplemented, and `lustre/element/html` already has a `dialog` constructor.
  `atlas/ui/html`'s `value` workaround (ADR 0038, for `wa-input`/`wa-textarea`'s `defaultValue`
  split) is also unnecessary for native elements: Lustre's `vdom/diff` module already special-cases
  `"value"`/`"checked"`/`"selected"` as synced properties for any element, so plain
  `lustre/attribute.value` already does the right thing on native `<input>`/`<textarea>`/`<select>`.
  Both wrapper modules could therefore be deleted outright for five of the six components.
- `wa-dialog` (ADR 0039) gave real modal behavior — focus trap, Escape-to-cancel, a backdrop — for
  free. Native `<dialog>` provides the same thing, but only via the imperative
  `.showModal()`/`.close()` methods; an `open` *attribute* alone (what ADR 0039's declarative
  `attribute.open(...)` relied on) only makes it a plain non-modal block. This is exactly the
  "bespoke dialog" option ADR 0039 rejected as too much to hand-build — except the hand-building
  turns out to be small: one imperative call to open it, and the browser's own Escape/backdrop/
  form-submit paths all converge on the dialog's native `close` event to close it.

## Options considered

1. **Keep Web Awesome** — zero migration cost, but the owner wants the app's visual language to be
   Bootstrap's, and a component library is more than this app's six plain form controls need.
2. **Drop Web Awesome; dialogs as a plain conditionally-rendered div overlay** — simplest, zero new
   JS, matches Lustre's declarative style throughout. Rejected: loses native focus-trap and
   Escape-to-cancel, which ADR 0039 specifically adopted `wa-dialog` to get.
3. **Drop Web Awesome; dialogs as a real native `<dialog>` driven by `showModal()`/`close()` via a
   small FFI (chosen)** — keeps the focus-trap/Escape/backdrop behavior ADR 0039 wanted, at the
   cost of one small hand-written JS file (a pattern this codebase already uses for `timer`,
   `online`, `storage`, etc.) and wiring one `Effect` into each of the eight "open a confirmation"
   message handlers.

## Decision

We remove Web Awesome entirely and hand-write the styling in `frontend/assets/app.css`, matching
Bootstrap's class names and color values (`--bs-primary` `#0d6efd`, `--bs-secondary` `#6c757d`,
`--bs-danger` `#dc3545`, with hover/active shades) with no Bootstrap file involved. Structural chrome
(background, border, text) keeps using Atlas's own `--surface`/`--border`/`--text`/`--accent`
tokens; only the semantic button/focus colors come from Bootstrap's palette.

- **Assets**: `frontend/assets/webawesome/` is deleted; `gleam.toml` drops the Web Awesome
  stylesheet, `register.js` script, and the `wa-dark`/`wa-light` class-toggling inline script
  (nothing consumes those classes anymore — Atlas's CSS already follows `prefers-color-scheme`
  directly).
- **Interop**: `atlas/ui/html.gleam` and `atlas/ui/event.gleam` are deleted. Call sites use
  `lustre/element/html`, `lustre/event` and `lustre/attribute` directly (already imported
  everywhere they're needed), with `attribute.class("btn btn-primary"|"btn btn-secondary"|
  "btn btn-danger"|"btn btn-link")` replacing each `variant`/`appearance` attribute, and
  `"form-control"`/`"form-select"` added to inputs/textareas/selects.
- **Dialogs**: a new `atlas/ui/dialog` module replaces `wa.dialog`/`wa_event.on_hide`:
  - `dialog.view(id, label, on_hide, footer)` renders a native `<dialog>` with the question as a
    visible heading wired via `aria-labelledby`, and `footer` (the action buttons) wrapped in a
    `<form method="dialog">` so a plain `<button type="submit">` closes it natively — no `slot`
    attribute needed, since these are now just ordinary children.
  - `dialog.show(id)` is an `Effect` wrapping one FFI call, `showModal(id)` (in
    `atlas/ui/dialog.ffi.mjs`), which also lazily binds a backdrop-light-dismiss click handler the
    first time it opens (native `<dialog>`/`::backdrop` has no built-in light-dismiss). Each of the
    eight call sites' "open the confirmation" message handler (e.g. `RemoveClicked`) now returns
    `dialog.show(id)` instead of `effect.none()`.
  - No `open` attribute is ever set declaratively; openness is driven entirely by the `showModal()`
    effect plus the browser's own Escape/backdrop/form-submit closing paths, all of which fire the
    native `close` event `on_hide` is wired to — keeping a page's `Model` and the dialog's actual
    state in sync exactly like `wa-hide` did, just via the browser's own event instead of Web
    Awesome's.

## Consequences

- No more vendored third-party component library: `frontend/assets/` holds only Atlas's own CSS and
  the Strava brand assets, and `app.css` is the only stylesheet again.
- `atlas/ui/dialog.ffi.mjs` is the first FFI this codebase has written purely for DOM/UI behavior
  (the rest — `timer`, `online`, `storage`, `clock`, `random`, `store`, `http`, `pwa` — are all data/
  platform glue); future UI behavior that needs an imperative DOM API follows the same shape.
  Several view functions (`coaches_page.given_view`, `sharing_page.share_view`,
  `workouts_page.workout_view`, `activities_page`/`assignments_page`'s `actions`,
  `today_page.status_view`, `plans_page.owner_actions`) no longer take a `Model`/`Bool` parameter
  they only used to compute a dialog's `open` attribute.
- Dropping Web Awesome also fixed an unrelated problem: this project's jsdom-based end-to-end test
  suite (`frontend/test-js/app.e2e.test.mjs`) could not reliably exercise `wa-*` custom elements in
  this environment (shadow-DOM-rendered buttons and inputs weren't found by plain
  `querySelectorAll("button")`), so 11 of its 38 tests failed before this change; with native
  elements, only 2 remain failing (pre-existing, unrelated to this change). jsdom also doesn't
  implement `HTMLDialogElement`'s `showModal()`/`close()` ([jsdom/jsdom#3294](https://github.com/jsdom/jsdom/issues/3294)),
  so `frontend/test-js/support.mjs` now polyfills the minimal behavior the app relies on, the same
  way it already shims `fetch`/`indexedDB`/`close()` for that test harness.
- Re-theming now means editing `app.css` directly; there is no vendored asset to re-pin on upgrade.
