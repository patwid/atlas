//// Small typed wrappers over Atlas's own text-field styling (ADR 0040, 0044), so call sites don't
//// repeat the `"md-text-field"` CSS class by hand. Named `field`, not `form`,
//// because `form` is already the usual parameter name for a page's form data (e.g.
//// `plan_form.Form`), which would shadow a module of that name.

import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute, class}
import lustre/element.{type Element}
import lustre/element/html

pub fn input(attributes: List(Attribute(msg))) -> Element(msg) {
  html.input([class("md-text-field"), ..attributes])
}

pub fn textarea(
  attributes: List(Attribute(msg)),
  content: String,
) -> Element(msg) {
  html.textarea([class("md-text-field"), ..attributes], content)
}

/// `options` are `#(value, label)` pairs. The current value is marked `selected` on its option
/// rather than set as the `<select>`'s `value`: the virtual DOM sets attributes before it adds the
/// children, so a `value` on the `<select>` itself finds no matching option yet and the first
/// option shows instead.
pub fn select(
  attributes: List(Attribute(msg)),
  value: String,
  options: List(#(String, String)),
) -> Element(msg) {
  html.select(
    [class("md-text-field"), ..attributes],
    list.map(options, fn(option) {
      html.option(
        [attribute.value(option.0), attribute.selected(option.0 == value)],
        option.1,
      )
    }),
  )
}

/// A field with a button at its end that opens a picker, such as a date field with a calendar button (ADR 0054).
pub fn with_trigger(
  field: Element(msg),
  trigger: Element(msg),
) -> Element(msg) {
  html.div([class("field-with-trigger")], [field, trigger])
}

// OUTLINED FIELDS WITH A FLOATING LABEL (ADR 0059) -------------------------------------------------

/// What a field says besides its label: a line of help under it, a unit at its end (`km`), and its error, which
/// replaces the help and marks the field.
pub type Help {
  Help(supporting: String, suffix: String, error: Option(String))
}

pub const plain = Help("", "", None)

pub fn help(supporting: String) -> Help {
  Help(..plain, supporting: supporting)
}

pub fn suffix(unit: String) -> Help {
  Help(..plain, suffix: unit)
}

/// Shows `error` when `error_field` is `field`: the form's problem is about this field (ADR 0059).
pub fn with_error(
  help: Help,
  field: String,
  error_field: String,
  error: Option(String),
) -> Help {
  case error_field == field {
    True -> Help(..help, error: error)
    False -> help
  }
}

/// An outlined text field whose label sits in the field and moves onto its outline when the field has focus or a
/// value, as Material 3 draws it.
pub fn text(
  id: String,
  label: String,
  help: Help,
  attributes: List(Attribute(msg)),
) -> Element(msg) {
  outlined(id, label, help, html.input(control(id, help, attributes)))
}

pub fn area(
  id: String,
  label: String,
  help: Help,
  attributes: List(Attribute(msg)),
  content: String,
) -> Element(msg) {
  outlined(
    id,
    label,
    help,
    html.textarea(control(id, help, attributes), content),
  )
}

/// A select with its label on the outline. `options` are `#(value, label)` pairs; see `select` for why the value
/// is marked on its option.
pub fn choose(
  id: String,
  label: String,
  help: Help,
  attributes: List(Attribute(msg)),
  value: String,
  options: List(#(String, String)),
) -> Element(msg) {
  outlined(
    id,
    label,
    help,
    html.select(
      control(id, help, attributes),
      list.map(options, fn(option) {
        html.option(
          [attribute.value(option.0), attribute.selected(option.0 == value)],
          option.1,
        )
      }),
    ),
  )
}

fn control(
  id: String,
  help: Help,
  attributes: List(Attribute(msg)),
) -> List(Attribute(msg)) {
  [
    attribute.id(id),
    class("md-text-field"),
    // A blank placeholder lets CSS tell an empty field (`:placeholder-shown`) from a filled one; a field's own
    // placeholder, given in `attributes`, takes its place.
    attribute.placeholder(" "),
    case help.error, help.supporting {
      None, "" -> attribute.none()
      _, _ -> attribute.attribute("aria-describedby", id <> "-help")
    },
    case help.error {
      Some(_) -> attribute.attribute("aria-invalid", "true")
      None -> attribute.none()
    },
    ..attributes
  ]
}

fn outlined(
  id: String,
  label: String,
  help: Help,
  input: Element(msg),
) -> Element(msg) {
  html.div(
    [
      class("md-field"),
      attribute.classes([
        #("has-error", help.error != None),
        #("has-suffix", help.suffix != ""),
      ]),
    ],
    [
      input,
      html.label([attribute.for(id), class("md-field-label")], [
        html.text(label),
      ]),
      case help.suffix {
        "" -> element.none()
        unit ->
          html.span(
            [
              class("md-field-suffix"),
              attribute.attribute("aria-hidden", "true"),
            ],
            [html.text(unit)],
          )
      },
      case help.error, help.supporting {
        // An error is announced when it appears, as the form-level message was (`atlas/ui/error`).
        Some(message), _ ->
          html.p(
            [
              attribute.id(id <> "-help"),
              class("md-field-supporting"),
              attribute.role("alert"),
            ],
            [html.text(message)],
          )
        None, "" -> element.none()
        None, text ->
          html.p([attribute.id(id <> "-help"), class("md-field-supporting")], [
            html.text(text),
          ])
      },
    ],
  )
}
