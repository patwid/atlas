//// A Material 3 menu (ADR 0056) behind an icon button, for an item's actions (Edit, Delete) or a page's less used
//// ones. It is a native popover, so the browser closes it on Escape, on a click outside and when an item is
//// chosen; `atlas/ui/interaction` places it under its button and moves between items with the arrow keys.

import atlas/ui/icon.{type Icon}
import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Item(msg) {
  Item(symbol: Icon, label: String, msg: msg)
}

/// `id` must be unique in the page; `label` names the button for screen readers ("More for Morning loop").
pub fn view(id: String, label: String, items: List(Item(msg))) -> Element(msg) {
  element.fragment([
    html.button(
      [
        attribute.type_("button"),
        class("md-icon-button md-menu-button"),
        attribute.attribute("popovertarget", id),
        attribute.attribute("aria-haspopup", "menu"),
        attribute.aria_label(label),
        attribute.title("More"),
      ],
      [icon.view(icon.MoreVert)],
    ),
    html.div(
      [
        attribute.id(id),
        class("md-menu"),
        attribute.attribute("popover", ""),
        attribute.role("menu"),
        attribute.aria_label(label),
      ],
      list.map(items, fn(item) {
        html.button(
          [
            attribute.type_("button"),
            class("md-menu-item"),
            attribute.role("menuitem"),
            attribute.attribute("popovertarget", id),
            attribute.attribute("popovertargetaction", "hide"),
            event.on_click(item.msg),
          ],
          [icon.view(item.symbol), html.text(item.label)],
        )
      }),
    ),
  ])
}
