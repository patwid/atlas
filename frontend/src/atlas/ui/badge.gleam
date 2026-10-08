//// Small labels shaped like Material 3 assist chips (ADR 0040, 0050): `badge` for a category such as a workout's
//// kind, `with_icon` for a state or origin such as "Public" or "Not synced yet", where the icon tells them apart
//// at a glance.

import atlas/ui/icon.{type Icon}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

pub fn badge(text: String) -> Element(msg) {
  html.span([class("badge")], [html.text(text)])
}

pub fn with_icon(symbol: Icon, text: String) -> Element(msg) {
  html.span([class("badge badge-icon")], [icon.view(symbol), html.text(text)])
}
