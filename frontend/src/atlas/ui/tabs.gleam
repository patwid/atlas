//// Material 3 primary tabs (ADR 0058): a row of tabs under the app bar and one panel per tab. Every panel is drawn
//// and the others are `hidden`, as the ARIA tabs pattern has it, so each keeps its state and what is in it can be
//// found. `atlas/ui/interaction` moves between tabs with the arrow keys.

import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Tab(msg) {
  Tab(key: String, label: String, content: Element(msg))
}

/// `id` keeps the tabs' and panels' ids apart from others on the page; `selected` is a tab's `key`.
pub fn view(
  id: String,
  selected: String,
  tabs: List(Tab(msg)),
  on_select: fn(String) -> msg,
) -> Element(msg) {
  let tab_id = fn(key) { id <> "-tab-" <> key }
  let panel_id = fn(key) { id <> "-panel-" <> key }
  html.div([class("md-tabs")], [
    html.div(
      [class("md-tab-bar"), attribute.role("tablist")],
      list.map(tabs, fn(tab) {
        let active = tab.key == selected
        html.button(
          [
            attribute.type_("button"),
            attribute.id(tab_id(tab.key)),
            class("md-tab"),
            attribute.role("tab"),
            attribute.attribute("aria-selected", case active {
              True -> "true"
              False -> "false"
            }),
            attribute.attribute("aria-controls", panel_id(tab.key)),
            attribute.attribute("tabindex", case active {
              True -> "0"
              False -> "-1"
            }),
            event.on_click(on_select(tab.key)),
          ],
          [html.span([class("md-tab-label")], [html.text(tab.label)])],
        )
      }),
    ),
    ..list.map(tabs, fn(tab) {
      html.div(
        [
          attribute.id(panel_id(tab.key)),
          class("md-tab-panel"),
          attribute.role("tabpanel"),
          attribute.attribute("aria-labelledby", tab_id(tab.key)),
          attribute.hidden(tab.key != selected),
        ],
        [tab.content],
      )
    })
  ])
}
