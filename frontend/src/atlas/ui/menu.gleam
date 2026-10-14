//// A menu (ADR 0056) behind an icon button, for an item's actions (Edit, Delete) or a page's less used ones: Fluent
//// UI's menu (ADR 0133). It opens its list as a popover under the button, moves between items with the arrow keys,
//// and closes on Escape, on a click outside and when an item is chosen.

import atlas/ui/button
import atlas/ui/icon.{type Icon}
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Item(msg) {
  Item(symbol: Icon, label: String, msg: msg)
}

/// `id` must be unique in the page; `label` names the button for screen readers ("More for Morning loop").
pub fn view(id: String, label: String, items: List(Item(msg))) -> Element(msg) {
  element.element("fluent-menu", [], [
    button.icon(
      [
        attribute.type_("button"),
        attribute.attribute("slot", "trigger"),
        attribute.title("More"),
      ],
      icon.MoreVert,
      label,
    ),
    element.element(
      "fluent-menu-list",
      [attribute.id(id), attribute.aria_label(label)],
      list.map(items, fn(item) {
        element.element("fluent-menu-item", [event.on_click(item.msg)], [
          html.span([attribute.attribute("slot", "start")], [
            icon.view(item.symbol),
          ]),
          html.text(item.label),
        ])
      }),
    ),
  ])
}
