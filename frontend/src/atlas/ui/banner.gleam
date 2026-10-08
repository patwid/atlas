//// A Material 3 style banner (ADR 0049): a prominent message at the top of the content, with an icon and up to
//// two actions, for something the user should act on or know about until it is resolved (being offline, sync
//// problems). Short confirmations are snackbars instead (`atlas/ui/snackbar`).

import atlas/ui/icon.{type Icon}
import lustre/attribute.{type Attribute, class}
import lustre/element.{type Element}
import lustre/element/html

/// `attributes` carry the banner's role and look (a class such as `"banner-error"`); `body` is the message and
/// `actions` its buttons.
pub fn view(
  attributes: List(Attribute(msg)),
  symbol: Icon,
  body: List(Element(msg)),
  actions: List(Element(msg)),
) -> Element(msg) {
  html.div([class("banner"), ..attributes], [
    html.div([class("banner-body")], [
      icon.view(symbol),
      html.div([class("banner-text")], body),
    ]),
    case actions {
      [] -> element.none()
      _ -> html.div([class("banner-actions")], actions)
    },
  ])
}
