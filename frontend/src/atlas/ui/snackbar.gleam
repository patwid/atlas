//// A Material 3 snackbar (ADR 0047): a short message about something the app just did, at the bottom of the
//// screen, with at most one action and a button to close it. The page keeps the message in its `Model` and
//// closes it on `on_close`. It is announced to screen readers as a status.
////
//// Errors are not snackbars: they stay next to the form or item they are about (`atlas/ui/error`).

import atlas/ui/button
import atlas/ui/icon
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Action(msg) {
  /// A link, such as "Open" for something the app just made.
  Link(label: String, href: String)
}

pub fn view(
  text: String,
  action: Option(Action(msg)),
  on_close: msg,
) -> Element(msg) {
  html.div([class("snackbar"), attribute.role("status")], [
    html.span([class("snackbar-text")], [html.text(text)]),
    case action {
      Some(Link(label, href)) ->
        html.a(
          [
            class("md-button md-button-text snackbar-action"),
            attribute.href(href),
          ],
          [html.text(label)],
        )
      None -> element.none()
    },
    button.icon(
      [attribute.type_("button"), event.on_click(on_close)],
      icon.Close,
      "Close",
    ),
  ])
}
