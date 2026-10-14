//// A slider with its label and value above it (ADR 0051), such as a week's or a rep's intensity: a native range
//// input drawn like Fluent UI's (ADR 0133), whose own slider sends `change` also when the page sets its value.

import atlas/ui/field.{type Help}
import gleam/option.{None, Some}
import lustre/attribute.{type Attribute, class}
import lustre/element.{type Element}
import lustre/element/html

/// `value_text` is the value as it is shown and read out ("80 %"); `fill` is how far the active track reaches, as a
/// percentage, for browsers that cannot draw it themselves. `attributes` give the range input its name, bounds, value
/// and events. `help` is a line under the slider, or its error.
pub fn view(
  id: String,
  label: String,
  value_text: String,
  fill: String,
  help: Help,
  attributes: List(Attribute(msg)),
) -> Element(msg) {
  let described = help.error != None || help.supporting != ""
  html.div(
    [
      class("intensity-setting"),
      attribute.classes([#("has-error", help.error != None)]),
    ],
    [
      html.div([class("intensity-heading")], [
        html.label([attribute.for(id)], [html.text(label)]),
        html.output([attribute.for(id), class("intensity-value")], [
          html.text(value_text),
        ]),
      ]),
      html.div([class("intensity-control")], [
        html.input([
          attribute.id(id),
          attribute.type_("range"),
          attribute.attribute("aria-valuetext", value_text),
          case described {
            True -> attribute.attribute("aria-describedby", id <> "-help")
            False -> attribute.none()
          },
          attribute.style("--fill", fill),
          ..attributes
        ]),
      ]),
      case described {
        False -> element.none()
        True ->
          html.p(
            [
              attribute.id(id <> "-help"),
              class("field-help"),
              ..case help.error {
                Some(_) -> [attribute.role("alert")]
                None -> []
              }
            ],
            [
              html.text(case help.error {
                Some(message) -> message
                None -> help.supporting
              }),
            ],
          )
      },
    ],
  )
}

/// The setting for someone who cannot change it: the label and value, and `bar` showing it.
pub fn read_only(
  label: String,
  value_text: String,
  bar: Element(msg),
) -> Element(msg) {
  html.div([class("intensity-setting")], [
    html.div([class("intensity-heading")], [
      html.span([], [html.text(label)]),
      html.span([class("intensity-value")], [html.text(value_text)]),
    ]),
    bar,
  ])
}
