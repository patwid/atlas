//// An empty state (ADR 0050): an icon, a headline and a line of help, with an optional action, for a list with
//// nothing in it yet or a page that is not there.

import atlas/ui/icon.{type Icon}
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

pub fn view(
  symbol: Icon,
  headline: String,
  text: String,
  action: Option(Element(msg)),
) -> Element(msg) {
  html.div([class("empty")], [
    icon.view(symbol),
    html.h2([], [html.text(headline)]),
    html.p([], [html.text(text)]),
    case action {
      Some(action) -> action
      None -> element.none()
    },
  ])
}

/// A smaller empty state for a list with a form or more content under it, such as the coaches with the field to
/// add one (ADR 0069), so what to do next stays in view on a phone.
pub fn compact(symbol: Icon, headline: String, text: String) -> Element(msg) {
  html.div([class("empty empty-compact")], [
    icon.view(symbol),
    html.h2([], [html.text(headline)]),
    html.p([], [html.text(text)]),
  ])
}

/// A link that reads as the empty state's action: a tonal button.
pub fn link(href: String, label: String) -> Element(msg) {
  html.a([class("md-button md-button-tonal"), attribute.href(href)], [
    html.text(label),
  ])
}
