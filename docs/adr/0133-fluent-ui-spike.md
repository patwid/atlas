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

- The bundle is vendored unchanged in `frontend/src/atlas/ui/fluent/` and imported by `atlas/ui/fluent`, which `main`
  calls before the app starts. esbuild bundles it into `atlas.js`, which grows from 382 KB to 657 KB, all precached.
- `frontend/assets/fluent-theme.css` holds Fluent 2's web light and dark themes as custom properties, dark under
  `prefers-color-scheme`, so the theme follows the system without JavaScript (Fluent's own `setTheme` is JavaScript).
- jsdom defines the elements and draws their shadow DOM, but each form control throws when it connects: jsdom's
  `ElementInternals` has no form half (`setFormValue`, `setValidity`, `form`). A shim of about 25 lines in
  `test-js/support.mjs` fills it in; with it the whole-app tests pass with Fluent loaded.

## Consequences

To be written when the owner decides.
