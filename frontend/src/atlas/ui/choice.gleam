//// Picking one of a few options (ADR 0047), as Material 3 segmented buttons or a set of filter chips. Both are a
//// group of native radio buttons, so the keyboard and screen readers treat them as one choice, styled as M3
//// draws them. `options` are `#(value, label)` pairs; `name` must be unique in the page.
////
//// Segmented buttons suit two to five short options; chips suit more, wrapping onto several lines.

import atlas/ui/icon
import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn segmented(
  name: String,
  legend: String,
  value: String,
  options: List(#(String, String)),
  on_change: fn(String) -> msg,
) -> Element(msg) {
  group("segmented", name, legend, value, options, on_change)
}

pub fn chips(
  name: String,
  legend: String,
  value: String,
  options: List(#(String, String)),
  on_change: fn(String) -> msg,
) -> Element(msg) {
  group("chips", name, legend, value, options, on_change)
}

fn group(
  kind: String,
  name: String,
  legend: String,
  value: String,
  options: List(#(String, String)),
  on_change: fn(String) -> msg,
) -> Element(msg) {
  html.fieldset([class("choice " <> kind)], [
    html.legend([], [html.text(legend)]),
    html.div(
      [class("choice-options")],
      list.map(options, fn(option) {
        html.label([class("choice-option")], [
          html.input([
            attribute.type_("radio"),
            attribute.name(name),
            attribute.value(option.0),
            attribute.checked(option.0 == value),
            event.on_change(on_change),
          ]),
          html.span([class("choice-label")], [
            icon.view(icon.Check),
            html.text(option.1),
          ]),
        ])
      }),
    ),
  ])
}
