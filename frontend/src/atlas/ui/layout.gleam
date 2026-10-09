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

/// A section heading under the app bar's title: M3's list subheader (ADR 0069). The app bar holds the page's title,
/// so sections are `h2`.
pub fn subheader(text: String) -> Element(msg) {
  html.h2([class("subheader")], [html.text(text)])
}

/// The headline of a `list` item that opens a page. The whole item is the link (ADR 0069), so the rest of the row,
/// such as chips and supporting text, opens it too.
pub fn row_link(href: String, headline: String) -> Element(msg) {
  html.a([class("row-link"), attribute.href(href)], [html.text(headline)])
}

/// A list item that opens another page (ADR 0049): a leading icon, a headline, supporting text and a chevron.
/// The whole row is the link.
pub fn link_item(
  href: String,
  symbol: Icon,
  headline: String,
  supporting: String,
) -> Element(msg) {
  html.li([class("link-item")], [
    html.a([attribute.href(href)], [
      icon.view(symbol),
      html.span([class("link-item-text")], [
        html.span([class("link-item-headline")], [html.text(headline)]),
        html.span([class("link-item-supporting")], [html.text(supporting)]),
      ]),
      icon.view(icon.ChevronRight),
    ]),
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
