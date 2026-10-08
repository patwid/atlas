//// Atlas's own button styling (ADR 0040, 0044): a named constructor per variant instead of a raw CSS
//// class string typed out at every call site, where a typo (`"md-button md-button-filed"`) would silently
//// render an unstyled button.
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

/// A Material 3 filled button, for the main action.
pub fn primary(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  variant("md-button md-button-filled", attributes, children)
}

/// A Material 3 outlined button, for the actions next to the main one.
pub fn secondary(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  variant("md-button md-button-outlined", attributes, children)
}

/// A filled button in the error color, for an action that deletes or removes.
pub fn danger(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  variant("md-button md-button-danger", attributes, children)
}

/// A Material 3 text button: no background or border.
pub fn link(
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
