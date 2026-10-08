//// Simple classed container wrappers repeated across almost every page (ADR 0040), so the class
//// name lives in one place instead of being retyped at each call site.

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
