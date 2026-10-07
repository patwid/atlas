# 0037. Adopt Shoelace web components for UI controls

- Status: Superseded by [0038](0038-migrate-shoelace-to-web-awesome.md)
- Date: 2026-10-07
- Deciders: project owner

## Context

ADR 0013 chose native HTML elements styled by one plain CSS file (`frontend/assets/app.css`),
explicitly "No CSS framework". There is still no UI component library: every button, input,
select and form across the 13-14 view modules under `frontend/src/atlas/` is built directly with
Lustre's `html.*` DSL and styled through hand-written classes (`.cards`, `.pill`, `.zones-form`,
and so on). That is roughly 55 buttons, 19 inputs and 7 forms/selects today, and each new control
(a date picker, a combobox, a dialog) means writing its markup, styling and accessibility
behaviour by hand.

The owner wants to adopt [Shoelace](https://shoelace.style), a framework-agnostic library of
accessible custom elements built on Lit. Because Shoelace ships as standard custom elements
rather than a JS framework, it can be used from any DOM, including Lustre's — but Lustre is a
VDOM framework (ADR 0003) whose `html.*`/`event.on_input`/`event.on_click` helpers assume native
elements and native event names. Shoelace components fire their own events (`sl-input`,
`sl-change`, `sl-select`, `sl-show`, `sl-hide`, ...) and some state (e.g. `sl-select`'s selected
value) is exposed as a JS property rather than a reflected attribute.

Atlas is also offline-first (ADR 0004) and installable as a PWA (ADR 0013), so any new asset
needs to be servable from `pb_public` without a runtime dependency on a CDN.

## Options considered

1. **Keep native elements and hand-written CSS (status quo)** — zero new dependency, but every
   richer control (dialogs, comboboxes, date pickers) is built and made accessible from scratch,
   and the owner has asked to move off this.
2. **Adopt a JS-framework UI kit (e.g. React + MUI)** — would mean adopting a JS framework,
   which contradicts the owner's stack requirement in ADR 0003. Rejected.
3. **Adopt Shoelace, CDN-loaded** — least setup, but adds a runtime dependency on an external
   host and needs service-worker caching to keep working offline; fits poorly with ADR 0013's
   app-shell model, which precaches a fixed, versioned file list.
4. **Adopt Shoelace, self-hosted (chosen)** — vendor Shoelace's pre-bundled "CDN build" (plain
   ES modules and CSS, no npm bundler required) into `frontend/assets/`, serve it from
   `pb_public` like `app.css` today, and precache it in `sw.js` like the rest of the shell.
   Keeps the app fully offline-capable and avoids adding Node/npm to the toolchain (ADR 0006).

## Decision

We will adopt Shoelace, self-hosted, and migrate every current native interactive control
(buttons, inputs, selects, textareas, forms) across all view modules to its Shoelace equivalent.

- **Assets**: vendor Shoelace 2.20.1's CDN-build distribution under `frontend/assets/shoelace/`,
  committed to the repo — the same "pin it, commit it" posture as `.tool-versions` (ADR 0006). Only
  the five components Atlas uses (`button`, `input`, `textarea`, `select`, `option`) and their
  shared `chunks/` are vendored, imported from one `register.js` entry; the autoloader and the
  icon set are left out, since every icon these five components need comes from Shoelace's inline
  "system" icon library, not the fetched "default" one. No build-time fetch, so no change to the
  sandbox's network policy (ADR 0007) is needed. The files are wired into the HTML shell the same
  way `app.css` is today (`gleam.toml`'s `[tools.lustre.html]`), and added to the precache list
  `scripts/build-frontend.sh` stamps into `sw.js` (ADR 0013).
- **Interop**: two small, logic-free Gleam modules, `atlas/ui/html` and `atlas/ui/event`, mirror
  `lustre/element/html` and `lustre/event` for the five Shoelace tags: `atlas/ui/html` is each tag
  as `lustre/element.element(tag, attributes, children)`, and `atlas/ui/event` is `on_input`/
  `on_change` decoders for Shoelace's `sl-input`/`sl-change` events, built the same way
  `lustre/event`'s own decoders read `event.target.value`. No FFI was needed: Shoelace's `value`
  is a reflected attribute, and `sl-button`'s clicks are native `click` events, so `event.on_click`
  already works unchanged.
- **Theming**: `app.css` aliases `--sl-color-primary-*` to Shoelace's own `--sl-color-teal-*` scale
  once in `:root` (the app's `--accent` already *is* Tailwind teal-700/teal-400), plus
  `--sl-font-sans` and `--sl-border-radius-medium` to match the app's existing look. Shoelace's
  `dark.css` theme is vendored too and gated behind a `.sl-theme-dark` class that a small inline
  script (in `gleam.toml`'s `scripts`) toggles from `prefers-color-scheme`, since dark.css's
  `--sl-color-teal-*` redefinition is what the primary alias actually needs in dark mode; nothing
  else in the app uses a class for theming. `app.css` keeps everything Shoelace has no equivalent
  for: page layout, the tab bar, badges/pills, the zones grid, and the Strava button's brand-locked
  styling.
- **Scope**: full migration. All view modules move their buttons, inputs, selects, textareas and
  forms onto the Shoelace wrappers, except the Strava "Connect" button and its attribution images
  (`strava_page.gleam`), which keep their brand-locked native markup unchanged — a Shoelace
  `sl-button` would add shadow-DOM chrome Strava's brand rules forbid.

## Consequences

- Dialogs, selects, form validation states and similar get Shoelace's accessibility behaviour for
  free instead of being hand-built.
- `app.css` shrinks to layout and the few brand-locked exceptions; most control styling moves to
  Shoelace's own stylesheet and `--sl-*` tokens.
- Shadow DOM means the existing global CSS selectors can't reach into a Shoelace component's
  internals; anything not exposed as a `--sl-*` custom property or an exported `::part()` can't be
  restyled.
- Vendored assets must be re-pinned by hand on upgrade (no package manager to bump a version for
  us), mirroring how `.tool-versions` upgrades already work (ADR 0006). Adding a sixth component
  later means vendoring its entry file alongside the existing `chunks/`.
- `attribute.autofocus` cannot be used on a Shoelace input: Lustre focuses a freshly-inserted
  element in a `queueMicrotask` right after mount, racing Shoelace's own (Lit) first render: if
  `sl-input.focus()` runs first, its internal input is still unset and it throws. The two forms
  that had it (`plans_page`, `workouts_page`) simply drop it.
- This narrows, rather than reverses, ADR 0013's "no CSS framework": that line is about not
  pulling in a layout/utility CSS framework, which still holds — this ADR instead adopts a
  component *library*. ADR 0013's styling section is annotated to point here.
