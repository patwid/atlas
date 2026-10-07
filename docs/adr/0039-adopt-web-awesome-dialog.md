# 0039. Adopt Web Awesome's dialog for confirmation prompts

- Status: Superseded by [0040](0040-drop-web-awesome.md)
- Date: 2026-10-07
- Deciders: project owner

## Context

Every destructive or hard-to-undo action in Atlas (deleting a plan, a workout or an activity;
removing a coach's access or a plan share; disconnecting Strava; unlinking a matched activity;
removing an assignment) asks for confirmation the same hand-built way: the row's normal action
buttons are replaced, in place, with a short question and "Yes, do it" / "Keep it" buttons, driven
by an `Option(id)` or `Bool` field on the page's `Model`. This works, but it is entirely hand-rolled:
no focus trap, no built-in Escape-to-cancel, no backdrop, and the question only reads as a plain
`<span role="alert">` rather than something a screen reader announces as a dialog.

ADR 0038 moved Atlas from Shoelace to Web Awesome for its five existing form controls (`button`,
`input`, `textarea`, `select`, `option`). Web Awesome also ships a `dialog` component (a styled
wrapper around the native `<dialog>` element) that gives exactly this: focus trapping, Escape and
optional light-dismiss, scroll locking, and a `wa-hide` event fired uniformly for every way a
dialog can be asked to close. The owner asked to look into adopting more Web Awesome components
where it's a good fit; confirmation prompts are the clearest match.

## Options considered

1. **Keep the hand-built inline confirm pattern** — zero migration cost, but each of the eight
   call sites re-implements the same accessibility gaps, and new ones (any future destructive
   action) would repeat them again.
2. **Adopt `wa-dialog` for confirmations (chosen)** — replaces the inline swap with a real modal,
   vendored the same way as ADR 0038's five components.
3. **Build a bespoke Gleam confirm-dialog abstraction on top of native `<dialog>`** — would give
   the same native behaviour without a new dependency, but means hand-building the focus trap,
   animation and backdrop that `wa-dialog` already provides, for a part of the app (modals) that
   ADR 0037/0038 identified as exactly where a component library pays for itself.

## Decision

We vendor a sixth Web Awesome component, `dialog`, the same way as ADR 0038's five: its entry file
and the transitive closure of `chunks/` it imports, fetched from the same pre-bundled CDN build
(`ka-f.webawesome.com`), added to `register.js`. No extra CSS was needed — `wa-dialog`'s backdrop
and spacing tokens (`--wa-color-overlay-modal`, cascade layers) were already pulled in by ADR
0038's `themes/default.css`.

- **Interop**: `atlas/ui/html` gains a `dialog` constructor (element, attributes, children — the
  same shape as the other five). `atlas/ui/event` gains `on_hide(message: msg)`, wrapping Web
  Awesome's `wa-hide` event with no payload decoding (unlike the form-control events, there's no
  value to read). Every dialog wires this to the same message its own "Cancel"/"Keep it" button
  sends, so the dialog's `open` attribute (driven by the page's `Model`) and the dialog's actual
  open/closed state can't drift apart regardless of *how* it was closed — the header's built-in
  close button, Escape, a light-dismiss backdrop click, or an in-page button all converge on the
  one `wa-hide` event.
- **Call sites**: all eight existing confirmation prompts (`plans_page`, `workouts_page`,
  `activities_page`, `assignments_page`, `coaches_page`, `sharing_page`, `strava_page`,
  `today_page`) move from the inline button-swap to a `wa-dialog`. The confirmation's question
  becomes the dialog's `label` (its header), with no change to their logic — every one of these
  already kept an `Option(id)`/`Bool` field on its `Model` for exactly this, so the field now
  drives `attribute.open(...)` instead of a `case` branch. The row's normal action buttons (Edit,
  Delete, …) are no longer swapped out while confirming; they stay visible underneath the modal,
  which now floats above the whole page rather than appearing inline in the specific row.
- **`light-dismiss`** is enabled on every one of these: clicking the backdrop cancels, the same as
  Escape or the explicit "Keep it" button. None of these confirmations are so consequential that
  an accidental backdrop click closing them (defaulting to *not* taking the destructive action) is
  a problem — if anything, the safer failure mode.

## Consequences

- These eight confirmations get focus trapping, scroll locking and Escape-to-cancel for free,
  instead of being hand-built per call site.
- Every confirmation dialog element is now always present in the DOM (closed, via the `open`
  property) rather than only existing while confirming; `element.to_string`-based tests that
  assert the confirmation text appears when confirming is true still pass unchanged, since `label`
  is a plain reflected attribute, but a test asserting that confirmation text is *absent* when not
  confirming would no longer hold — no such assertion existed before this change.
- `atlas/ui/html`/`atlas/ui/event` now cover six components and three events; a future component
  follows the same pattern (vendor from `ka-f.webawesome.com`, add the matching Gleam wrapper).
- This still leaves the other Web Awesome component candidates surveyed alongside this change —
  `callout` for form error messages, `badge`/`tag` for the plan-visibility and offline pills,
  `card` for the plan list, `spinner` for loading states, `number-input` for the one numeric
  field — unadopted. None of those came up as a correctness or accessibility gap the way inline
  confirmation prompts did; they would be purely cosmetic swaps, left for a future ADR if wanted.
