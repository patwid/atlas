//// A small label like "Public" or "Not synced yet" (ADR 0040): collapses the repeated
//// `html.span([class("badge")], [html.text(text)])` shape into one call.

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

pub fn badge(text: String) -> Element(msg) {
  html.span([class("badge")], [html.text(text)])
}
