# 0133. Try Fluent UI's web components in place of the hand-written Material 3

- Status: Proposed
- Date: 2026-10-14
- Deciders: owner (asked to look into switching to Fluent UI); agent (the spike and the details below)

## Context

Since ADR 0044 Atlas looks like Material Design 3, written by hand in `app.css` on native elements, behind the
`atlas/ui` modules. Since ADR 0132 no page outside `atlas/ui` builds a control itself, so a change of design system
touches `atlas/ui` and the CSS only. The owner asked to look into [Fluent UI](https://fluent2.microsoft.design)
(Microsoft's Fluent 2) and to know which of Atlas's components have no Fluent equivalent before switching.

Fluent UI comes in two forms:

- `@fluentui/react-components` (v9), the complete one, is React. Atlas's views are Lustre (ADR 0003), so it is out.
- [`@fluentui/web-components`](https://www.npmjs.com/package/@fluentui/web-components) 3.1.3 (MIT): custom elements
  on FAST Element with shadow DOM. One pre-built bundle, `dist/web-components.min.js`, 274 KB (66 KB gzipped), has no
  imports. Its colours, type and shapes are CSS custom properties from `@fluentui/tokens` (1.0.0-alpha.24).

The web components have: accordion, avatar, badge, button, anchor-button, compound-button, toggle-button, checkbox,
counter-badge, dialog, divider, drawer (start or end edge only), dropdown (select or combobox), field, image, label,
link, menu, message-bar, progress-bar, radio-group, rating-display, slider, spinner, switch, tablist, text, text-input
(text, email, password, tel and url only), textarea, tooltip and tree.

They have **no equivalent** for these parts of Atlas: the floating action button (ADR 0067), the error button, the
date picker (ADR 0054), the time picker, the calendar's bottom sheet (ADR 0052), chips (ADR 0050), the snackbar with
undo (ADR 0056), the navigation bar and rail (ADR 0044, 0095), the app bar, lists and their rows (ADR 0069, 0132's
`row_button`), cards (ADR 0127), `number`, `date` and `time` inputs, and the read-only slider. Partial: the tonal
button (Fluent's default button is close), the connected button group (toggle buttons), the full-screen form dialog
(a full-size drawer) and the simple dialog's choices (no list). Most of the missing ones are the phone patterns the
app is built around; they would stay hand-written, in Fluent's tokens.

ADR 0040 dropped Web Awesome partly because the whole-app tests run in jsdom, which did not get on with shadow DOM.

## Options considered

1. **Fluent UI web components** behind `atlas/ui`, the missing parts hand-written with Fluent's tokens.
2. **Fluent 2 by hand**: Fluent's tokens in CSS on the native elements Atlas has now, as ADR 0044 did for M3. No new
   JavaScript, no shadow DOM, the same look.
3. **Stay with Material 3** (ADR 0044).

## Decision

Not decided yet. A spike on the branch `fluent-ui-spike` tries option 1 on the parts that decide it (see Spike), so
the owner can choose between 1 and 2 knowing what each costs.

## Spike

On the branch `fluent-ui-spike`, Atlas's filled, tonal, outlined and text buttons (`atlas/ui/button`) and its
confirmation dialog (`dialog.view`) are Fluent UI's. Everything else is still M3, so the branch mixes the two looks.
All 730 unit tests and all 49 whole-app tests pass.

- **Loading.** The bundle is vendored unchanged in `frontend/src/atlas/ui/fluent/` and imported by `atlas/ui/fluent`,
  which `main` calls before the app starts, only where there are custom elements: the unit tests import the app in
  Node, where the bundle cannot run. esbuild bundles it into `atlas.js`, which grows from 382 KB to 657 KB, all
  precached.
- **Theme without JavaScript.** `frontend/assets/fluent-theme.css` holds Fluent 2's web light and dark themes from
  `@fluentui/tokens` as custom properties, dark under `prefers-color-scheme`. Fluent's own `setTheme` is not needed.
  `createLightTheme` and `createDarkTheme` can make the ramp from Atlas's blue (`#0d6efd`) instead of Fluent's.
- **jsdom.** It defines the elements and draws their shadow DOM, but each form control throws when it connects:
  jsdom's `ElementInternals` has no form half (`setFormValue`, `setValidity`, `form`), and it has no
  `requestSubmit`. A shim of about 30 lines in `test-js/support.mjs` fills them in. The tests' helpers look for
  `fluent-button` beside `button`, five selectors in the tests did the same, and `openDialog` looks into a Fluent
  dialog's shadow root. Two unit tests checked M3 class names. So the tests stay in jsdom, unlike under Web Awesome
  (ADR 0040), but they now run against a shim, which is checked only as far as the app uses it.
- **Real browser (Chromium).** A `fluent-button` with `form="…"` submits a form it is not in, as the form dialogs'
  Save needs (ADR 0085). Cancel and Escape close the dialog, and each fires one `toggle` to "closed".
- **Behaviour that differs from native elements:**
  - A `fluent-button` without a `type` does not submit the form it is in.
  - A `<form method="dialog">` cannot close a Fluent dialog, whose `<dialog>` is in its shadow root, so
    `atlas/ui/dialog.ffi.mjs` closes it on the form's submit. Fluent reports closing as a `toggle` event, not
    `close`.
  - Fluent passes `aria-labelledby` and `aria-describedby` on to the `<dialog>` in its shadow root, where the page's
    ids cannot be found. In Chromium the confirmation dialog had no name and no description. The name now comes
    from `aria-label`. **The sentence is no longer read out with the headline** (a step back from ADR 0124): Fluent
    passes on no text form of `aria-describedby` (ARIA 1.3's draft `aria-description`).
  - An alert dialog has no light-dismiss, so confirmations no longer close on a click outside (ADR 0039 chose that
    they do).
- **Fields stay out of the spike.** `fluent-text-input` has no `number`, `date` or `time` type, and `field.text`
  receives its type inside opaque attributes. So switching the fields needs a change to `field.text`'s signature at
  its 23 call sites, or a separate constructor for the native types.

## Consequences

To be written when the owner decides. What the spike suggests:

- Option 1 works in the tests and in Chromium, but every component swap needs this kind of checking (events, forms,
  ARIA across the shadow root) and a matching change to the shim. Half the components (see Context) would be
  hand-written anyway.
- Option 2 gives the same look with none of the above. `fluent-theme.css` is useful for either option.
- If option 1 is chosen: the next step is the fields, then the menus, and Fluent dialogs for the simple, details and
  form dialogs (their `data-open` handling in `atlas/ui/interaction`).
