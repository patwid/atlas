//// Atlas's buttons, named after Material Design 3's common buttons (ADR 0040, 0044, 0046): a constructor per
//// M3 button instead of a raw CSS class string typed out at every call site, where a typo
//// (`"md-button md-button-filed"`) would silently render an unstyled button.
////
//// M3 has no "danger" button: a destructive action is confirmed in a dialog, whose actions are both text
//// buttons, the dismissive one first.
////
//// `button` is the plain, unstyled base the variants below are built from; use it directly for a
//// button that must render with no styling of Atlas's own, such as Strava's brand connect button
//// (ADR 0027), so every button in the app still goes through this module.

import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html

pub fn button(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  html.button(attributes, children)
}

/// A filled button: the most important action on the screen, such as Save or New plan.
pub fn filled(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  variant("md-button md-button-filled", attributes, children)
}

/// An outlined button: an action next to the main one, such as Cancel or Delete.
pub fn outlined(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  variant("md-button md-button-outlined", attributes, children)
}

/// A text button: the lowest emphasis, for dialog actions and inline actions such as Clear.
pub fn text(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  variant("md-button md-button-text", attributes, children)
}

fn variant(
  class_names: String,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  button([attribute.class(class_names), ..attributes], children)
}
