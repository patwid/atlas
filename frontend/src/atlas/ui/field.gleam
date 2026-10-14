//// Atlas's text fields (ADR 0040, 0044): Fluent UI's text input and textarea (ADR 0133), and native inputs for the
//// types Fluent's text input does not have (number, date, time), styled to match. Named `field`, not `form`,
//// because `form` is already the usual parameter name for a page's form data (e.g.
//// `plan_form.Form`), which would shadow a module of that name.

import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute, class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn input(attributes: List(Attribute(msg))) -> Element(msg) {
  html.input([class("native-control"), ..attributes])
}

pub fn textarea(
  attributes: List(Attribute(msg)),
  content: String,
) -> Element(msg) {
  html.textarea([class("native-control"), ..attributes], content)
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
    [class("native-control"), ..attributes],
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

/// A hidden file input, opened by a button of its own through `atlas/file` (ADR 0100). `on_chosen` fires when a file
/// is picked.
pub fn file(id: String, on_chosen: msg) -> Element(msg) {
  html.input([
    attribute.type_("file"),
    attribute.id(id),
    attribute.hidden(True),
    attribute.attribute("tabindex", "-1"),
    event.on("change", decode.success(on_chosen)),
  ])
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

/// Fluent UI's text input with its label above it, for text, e-mail, password, telephone and URL fields: the types
/// it has. The label is inside the element, where Fluent connects it to the input in its shadow root;
/// `atlas/ui/fluent` copies `aria-describedby`, `aria-invalid` and `inputmode` onto that input, which Fluent does
/// not (ADR 0133).
pub fn text(
  id: String,
  label: String,
  help: Help,
  attributes: List(Attribute(msg)),
) -> Element(msg) {
  fluent_field(
    id,
    help,
    element.element("fluent-text-input", fluent_control(id, help, attributes), [
      html.text(label),
      case help.suffix {
        "" -> element.none()
        unit ->
          html.span(
            [attribute.attribute("slot", "end"), class("field-suffix")],
            [html.text(unit)],
          )
      },
    ]),
  )
}

/// A native input with its label on the outline, for the types Fluent's text input does not have: `number`, `date`
/// and `time`, given in `attributes`. Styled to match Fluent's.
pub fn native(
  id: String,
  label: String,
  help: Help,
  attributes: List(Attribute(msg)),
) -> Element(msg) {
  outlined(id, label, help, html.input(control(id, help, attributes)))
}

/// Fluent UI's textarea. Its label goes in the `label` slot; its text content would be its default value, so
/// `content` is set as its value instead.
pub fn area(
  id: String,
  label: String,
  help: Help,
  attributes: List(Attribute(msg)),
  content: String,
) -> Element(msg) {
  fluent_field(
    id,
    help,
    element.element(
      "fluent-textarea",
      [
        attribute.value(content),
        // Full width, and taller as more is written.
        attribute.attribute("block", ""),
        attribute.attribute("auto-resize", ""),
        ..fluent_control(id, help, attributes)
      ],
      [html.span([attribute.attribute("slot", "label")], [html.text(label)])],
    ),
  )
}

fn fluent_control(
  id: String,
  help: Help,
  attributes: List(Attribute(msg)),
) -> List(Attribute(msg)) {
  [
    attribute.id(id),
    attribute.attribute("appearance", "outline"),
    attribute.attribute("control-size", "large"),
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

fn fluent_field(id: String, help: Help, control: Element(msg)) -> Element(msg) {
  html.div(
    [class("field"), attribute.classes([#("has-error", help.error != None)])],
    [control, supporting(id, help)],
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
    class("native-control"),
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
      class("native-field"),
      attribute.classes([
        #("has-error", help.error != None),
        #("has-suffix", help.suffix != ""),
      ]),
    ],
    [
      input,
      html.label([attribute.for(id), class("field-label")], [
        html.text(label),
      ]),
      case help.suffix {
        "" -> element.none()
        unit ->
          html.span(
            [
              class("native-suffix"),
              attribute.attribute("aria-hidden", "true"),
            ],
            [html.text(unit)],
          )
      },
      supporting(id, help),
    ],
  )
}

/// The line under a field: its error, announced when it appears as the form-level message was (`atlas/ui/error`),
/// or else its help.
fn supporting(id: String, help: Help) -> Element(msg) {
  case help.error, help.supporting {
    Some(message), _ ->
      html.p(
        [
          attribute.id(id <> "-help"),
          class("field-help"),
          attribute.role("alert"),
        ],
        [html.text(message)],
      )
    None, "" -> element.none()
    None, text ->
      html.p([attribute.id(id <> "-help"), class("field-help")], [
        html.text(text),
      ])
  }
}
