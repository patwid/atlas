# 0059. Floating labels, units and errors on the field they are about

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked to go ahead with the Material review's next steps); agent (the details below)

## Context

Form fields had their label above the outline, units and formats in the label ("Distance (km)", "Time (minutes or
h:mm)"), and a form's problem as one message at its end, whatever field it was about. Material Design 3 (M3) puts
the label inside the outlined field (moving onto the outline when the field has focus or a value), a unit as a suffix
in the field, a format as supporting text under it, and an error under the field it is about, which is marked.

## Decision

- **Fields**: `field.text`, `field.area` and `field.choose` draw an outlined field with a floating label, done in CSS
  (`:placeholder-shown` with a blank placeholder, `:focus-within`), and a `Help`: supporting text, a suffix, and an
  error that replaces the supporting text, turns the field red, sets `aria-invalid` and `aria-describedby`, and is
  announced (`role="alert"`). Date, time and select fields always show their label on the outline. A field's own
  placeholder shows only while it has focus. The label's background is `--field-container`, the colour of what the
  field sits on.
- **Validation**: each form module (`activity_form`, `workout_form`, `plan_form`, `assignment_form`) checks in
  `validate_fields`, whose problem names its field (`#("distance", "…")`); `validate` keeps returning the message
  alone, and `error_field(form)` names the field of the form's problem, for the view. A problem about no single field
  (such as one the server sent back) still shows at the end of the form.
- **Forms converted**: plan, plan settings (a phases problem shows under the phases), workout, activity, schedule,
  sign-in, the person finder, and the two main fields of training zones. The zones' grid keeps a label beside each
  small field, as a table would.

## Consequences

- Labels are short ("Distance", "Time") and units and formats sit where M3 puts them; optional fields say so in their
  supporting text.
- The error is where the eye is; tests find it by `role="alert"` and the field by `aria-invalid`.
