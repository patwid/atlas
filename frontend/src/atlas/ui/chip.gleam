//// Small non-interactive chips (ADR 0040, 0050, 0062), shaped like Material 3's assist chips: `label` for a
//// category such as a workout's kind, `with_icon` for a state or origin such as "Public" or "Not synced yet", where
//// the icon tells them apart at a glance. (M3's "badge" is a notification count, as on the Settings tab; these are
//// chips.)

import atlas/ui/icon.{type Icon}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

pub fn label(text: String) -> Element(msg) {
  html.span([class("label-chip")], [html.text(text)])
}

pub fn with_icon(symbol: Icon, text: String) -> Element(msg) {
  html.span([class("label-chip")], [icon.view(symbol), html.text(text)])
}

/// A row of chips after a headline.
pub fn row(chips: List(Element(msg))) -> Element(msg) {
  html.span([class("chip-row")], chips)
}
