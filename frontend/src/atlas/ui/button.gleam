//// Atlas's buttons, named after Material Design 3's common buttons (ADR 0040, 0044, 0046, 0047): a constructor per
//// M3 button instead of a raw CSS class string typed out at every call site, where a typo
//// (`"md-button md-button-filed"`) would silently render an unstyled button.
////
//// M3 has no "danger" button: a destructive action is confirmed in a dialog, whose actions are both text
//// buttons, the dismissive one first.
////
//// `button` is the plain, unstyled base the variants below are built from; use it directly for a
//// button that must render with no styling of Atlas's own, such as Strava's brand connect button
//// (ADR 0027), so every button in the app still goes through this module.

import atlas/ui/icon.{type Icon}
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

/// A filled tonal button: between filled and outlined, for an action that moves things forward but is not the
/// main one, such as Copy to my plans.
pub fn tonal(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  variant("md-button md-button-tonal", attributes, children)
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

/// An extended floating action button: the one main action of a screen, such as New plan, floating at the
/// bottom right above the navigation.
pub fn fab(
  attributes: List(Attribute(msg)),
  symbol: Icon,
  label: String,
) -> Element(msg) {
  button([attribute.class("md-fab"), ..attributes], [
    icon.view(symbol),
    // In a navigation rail the FAB shows its icon only; the label is still read (ADR 0060).
    html.span([attribute.class("fab-label")], [html.text(label)]),
  ])
}

/// An icon button, for a small action such as closing a snackbar. `label` names it for screen readers.
pub fn icon(
  attributes: List(Attribute(msg)),
  symbol: Icon,
  label: String,
) -> Element(msg) {
  button(
    [
      attribute.class("md-icon-button"),
      attribute.attribute("aria-label", label),
      ..attributes
    ],
    [icon.view(symbol)],
  )
}

fn variant(
  class_names: String,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  button([attribute.class(class_names), ..attributes], children)
}
