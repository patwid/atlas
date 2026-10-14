//// A banner (ADR 0049): a prominent message at the top of the content, with an icon and up to two actions, for
//// something the user should act on or know about until it is resolved (storage or sync problems). It is Fluent
//// UI's message bar (ADR 0133). Short confirmations are snackbars instead (`atlas/ui/snackbar`).

import atlas/ui/icon.{type Icon}
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

/// How serious the message is, which sets its color: an error, or a warning about something that went partly wrong.
pub type Intent {
  Error
  Warning
}

/// `attributes` carry the banner's role or announcement; `body` is the message and `actions` its buttons.
pub fn view(
  intent: Intent,
  attributes: List(Attribute(msg)),
  symbol: Icon,
  body: List(Element(msg)),
  actions: List(Element(msg)),
) -> Element(msg) {
  element.element(
    "fluent-message-bar",
    [
      attribute.class("banner"),
      attribute.attribute("layout", "multiline"),
      attribute.attribute("intent", case intent {
        Error -> "error"
        Warning -> "warning"
      }),
      ..attributes
    ],
    [
      html.span([attribute.attribute("slot", "icon")], [icon.view(symbol)]),
      html.div([attribute.class("banner-text")], body),
      case actions {
        [] -> element.none()
        _ -> html.div([attribute.attribute("slot", "actions")], actions)
      },
    ],
  )
}
