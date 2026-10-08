//// Simple classed container wrappers repeated across almost every page (ADR 0040), so the class
//// name lives in one place instead of being retyped at each call site.

import atlas/ui/icon.{type Icon}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// A row of action buttons: Edit/Delete, Save/Cancel, and the like.
pub fn actions(children: List(Element(msg))) -> Element(msg) {
  html.div([class("actions")], children)
}

/// A Material 3 list (ADR 0047): plans, coaches, shares, athletes, and the like. Each item's link is its
/// headline and its paragraphs the supporting text.
pub fn list(children: List(Element(msg))) -> Element(msg) {
  html.ul([class("list")], children)
}

/// A list item that opens another page (ADR 0049): a leading icon, a headline, supporting text and a chevron.
/// The whole row is the link.
/// `selected` marks the row of the page on show, when the list stays beside it (ADR 0060).
pub fn link_item(
  href: String,
  symbol: Icon,
  headline: String,
  supporting: String,
  selected: Bool,
) -> Element(msg) {
  html.li([class("link-item")], [
    html.a(
      [
        attribute.href(href),
        case selected {
          True -> attribute.attribute("aria-current", "page")
          False -> attribute.none()
        },
      ],
      [
        icon.view(symbol),
        html.span([class("link-item-text")], [
          html.span([class("link-item-headline")], [html.text(headline)]),
          html.span([class("link-item-supporting")], [html.text(supporting)]),
        ]),
        icon.view(icon.ChevronRight),
      ],
    ),
  ])
}

/// A list item that shows something rather than opening a page (ADR 0055), laid out like `link_item`, with an
/// optional control at its end.
pub fn info_item(
  symbol: Icon,
  headline: String,
  supporting: String,
  trailing: Element(msg),
) -> Element(msg) {
  html.li([class("info-item")], [
    icon.view(symbol),
    html.span([class("link-item-text")], [
      html.span([class("link-item-headline")], [html.text(headline)]),
      html.span([class("info-item-supporting")], [html.text(supporting)]),
    ]),
    trailing,
  ])
}
