# 0134. Native controls where Fluent UI's components do not fit, and the rest in Fluent's look

- Status: Accepted
- Date: 2026-10-14
- Deciders: agent (while carrying out the owner's choice of ADR 0133)

## Context

[ADR 0133](0133-fluent-ui-spike.md) moved Atlas to Fluent 2: where Fluent UI's web components have a component,
`atlas/ui` draws it, and the parts Fluent has none for stay Atlas's own in Fluent's tokens. It listed selects, radio
groups and sliders among the components Fluent would draw. Swapping each one, checked in jsdom and in Chromium,
showed that some of Fluent's components do not fit Atlas, and that others need help to be accessible:

- **Text input and textarea.** Only a label inside the element names the `<input>` in its shadow root: a
  `fluent-field` label or a `<label for>` does not. `aria-describedby`, `aria-invalid` and `inputmode` are not passed
  on, so a field's help and error were not read out and a phone showed the full keyboard for a distance. The text
  input has no `number`, `date` or `time` type.
- **Dropdown.** It adds its own `<button role="combobox">` to its light DOM, the DOM Lustre owns, and a native
  `<select>` opens the phone's own picker.
- **Slider.** It sends only `change`, on every value change and also when its value is set from outside, so the week
  dialog would save while the page draws and on every step of a drag.
- **Dialog.** A `modal` dialog closes on a click outside, which would lose what was typed in a form (ADR 0057); an
  `alert` dialog has the `alertdialog` role, which is not a form's. Its `<dialog>` is in its shadow root, so the page's
  ids do not name or describe it.
- **Anchor button.** Its `<a>` is in its shadow root, so the router (modem), which looks for an `<a>` among the
  clicked element's ancestors, does not follow it and the browser loads the whole page.
- **Radio group.** It draws classic round radio buttons, a step back for the segmented buttons and chips (ADR 0047).
- **Menu.** It works: it places its list as a popover, moves between items with the arrow keys and closes on Escape,
  a click outside and a choice, which Atlas did by hand (ADR 0056).

## Options considered

1. **Use Fluent's component everywhere it has one**, working around each gap. The slider and dropdown problems are
   in how the components behave, not in what they pass on, so they cannot be shimmed from outside.
2. **Use Fluent's component where it fits, and a native element drawn like Fluent's where it does not (chosen).**

## Decision

We will use Fluent's component where it fits, and a native element drawn in Fluent's tokens where it does not.

- **Fluent's components**: buttons, icon buttons and the FAB (`fluent-button`), confirmation, simple and details
  dialogs (`fluent-dialog`), text fields and textareas, menus, the sync progress bar, spinners, banners
  (`fluent-message-bar`) and chips (`fluent-badge`).
- **Text fields** carry their label inside the element. `atlas/ui/fluent` watches the page and copies
  `aria-describedby` (as element references, which can reach from a shadow root out into the page), `aria-invalid`
  and `inputmode` onto the `<input>` or `<textarea>` in each one's shadow root.
- **Native, drawn like Fluent's**: number, date and time inputs (`field.native`), selects, the intensity slider, the
  form dialog and the date and time pickers, links that look like buttons (`.link-button`), and the segmented buttons
  and chips (radio buttons).
- **Atlas's own, in Fluent's tokens**, as Fluent's web components have none: the navigation bar and rail (Fluent 2's
  tab bar on a phone, a rail with a brand bar beside the current item on wider screens), the app bar, lists and the
  plan calendar, the snackbar (like Fluent's toast), empty states, the counter badge on Settings and the meters (like
  Fluent's determinate progress bar).
- **Icons** are Fluent System Icons (`@fluentui/svg-icons` 1.1.344, MIT): regular, and filled for the current
  navigation item.
- **Gone with Material 3**: the ripple, the state layers' M3 morphing shapes, M3 Expressive's springs (Fluent's curves
  and durations instead), the shape library (the loading indicator and the empty state's cookie), the floating
  labels (labels above the field, as in Fluent) and M3's letter-spacing. Type uses Fluent's size ramp.

## Consequences

- A field's help and error reach screen readers only with `atlas/ui/fluent`'s observer running, and only in browsers
  with ARIA element reflection (Chrome and Edge 135, Safari 16.4, Firefox 136 and later). jsdom does not show
  whether they do: they were checked in Chromium's accessibility tree.
- A confirmation dialog's sentence is still not read out with its headline (ADR 0133).
- Two kinds of field (Fluent's and native) and two kinds of dialog (Fluent's and native) are drawn alike by hand: a
  change to Fluent's look upstream does not reach the native ones.
- [ADR 0053](0053-material-3-expressive.md) and [0095](0095-expressive-navigation-progress-menus-motion.md) (M3
  Expressive) are superseded. [ADR 0051](0051-material-slider-progress-motion.md)'s slider look and ripple,
  [0056](0056-menus-and-undo.md)'s hand-made menus, [0059](0059-floating-labels-and-field-errors.md)'s floating
  labels and [0098](0098-medium-buttons-and-button-group.md)'s button sizes and widening group are changed by this
  ADR.
- Revisit a native control when Fluent's component gains what it lacks here (types on the text input, an `input`
  event on the slider, a dropdown that leaves its light DOM alone).
