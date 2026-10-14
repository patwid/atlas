//// Atlas's buttons, named after Material Design 3's common buttons (ADR 0040, 0044, 0046, 0047) and drawn as Fluent
//// UI's (ADR 0133): a constructor per kind of button instead of an element and its appearance typed out at every
//// call site.
////
//// Links that look like buttons (`text_link`, `icon_link`) stay native `<a>` elements styled like Fluent's buttons:
//// the router (modem) only follows a click on an `<a>` in the page, not one in a `fluent-anchor-button`'s shadow root.
////
//// M3 has no "danger" button: a destructive action is confirmed in a dialog, whose actions are both text
//// buttons, the dismissive one first.
////
//// `button` is the plain, unstyled base the variants below are built from; use it directly for a
//// button that must render with no styling of Atlas's own, such as Strava's brand connect button
//// (ADR 0027), so every button in the app still goes through this module.

import atlas/ui/icon.{type Icon}
import gleam/option.{type Option, None, Some}
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

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
  fluent("primary", attributes, children)
}

/// A filled tonal button: between filled and outlined, for an action that moves things forward but is not the
/// main one, such as Copy to my plans.
pub fn tonal(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  fluent("", attributes, children)
}

/// An outlined button: an action next to the main one, such as Cancel or Delete.
pub fn outlined(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  fluent("outline", attributes, children)
}

/// A text button: the lowest emphasis, for dialog actions and inline actions such as Clear.
pub fn text(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  fluent("subtle", attributes, children)
}

/// An extended floating action button: the one main action of a screen on a phone, such as New plan, floating at the
/// bottom right above the navigation bar (ADR 0067, 0068). Wider screens show it in the app bar instead.
pub fn fab(
  attributes: List(Attribute(msg)),
  symbol: Icon,
  label: String,
) -> Element(msg) {
  // Fluent has no floating action button: a large, round primary button, raised and placed by `.fab`.
  fluent(
    "primary",
    [
      attribute.class("fab"),
      attribute.attribute("size", "large"),
      attribute.attribute("shape", "circular"),
      ..attributes
    ],
    [
      icon.view(symbol),
      html.span([attribute.class("fab-label")], [html.text(label)]),
    ],
  )
}

/// Fluent's large button, for an action that is all a screen offers, such as signing in or an empty state's way on
/// (ADR 0098). Add it to a common button's attributes; buttons are medium otherwise.
pub fn medium() -> Attribute(msg) {
  attribute.attribute("size", "large")
}

/// M3 Expressive's standard button group (ADR 0098): buttons side by side, the one pressed widening while its
/// neighbours give way, such as a plan's Edit and More in the app bar.
pub fn group(children: List(Element(msg))) -> Element(msg) {
  html.div([attribute.class("button-group")], children)
}

/// An icon button, for a small action such as closing a snackbar. `label` names it for screen readers.
pub fn icon(
  attributes: List(Attribute(msg)),
  symbol: Icon,
  label: String,
) -> Element(msg) {
  fluent(
    "subtle",
    [
      attribute.class("icon-button"),
      attribute.attribute("icon-only", ""),
      attribute.attribute("size", "large"),
      attribute.attribute("aria-label", label),
      ..attributes
    ],
    [icon.view(symbol)],
  )
}

/// A link that looks like a text button, such as a dialog's way to another page.
pub fn text_link(href: String, children: List(Element(msg))) -> Element(msg) {
  html.a(
    [attribute.class("md-button md-button-text"), attribute.href(href)],
    children,
  )
}

/// A link that looks like an icon button, such as the app bar's back button. `label` names it for screen readers
/// and as its tooltip.
pub fn icon_link(
  attributes: List(Attribute(msg)),
  href: String,
  symbol: Icon,
  label: String,
) -> Element(msg) {
  html.a(
    [
      attribute.class("md-icon-button"),
      attribute.href(href),
      attribute.aria_label(label),
      attribute.title(label),
      ..attributes
    ],
    [icon.view(symbol)],
  )
}

/// Fluent UI's button (ADR 0133, spike) in one of its `appearance`s; "" is its default, secondary look. Unlike a native
/// button, a `fluent-button` without a `type` does not submit the form it is in.
fn fluent(
  appearance: String,
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  element.element(
    "fluent-button",
    [
      case appearance {
        "" -> attribute.none()
        _ -> attribute.attribute("appearance", appearance)
      },
      ..attributes
    ],
    children,
  )
}

/// A screen's main action (ADR 0068), such as New plan: on a phone a floating action button (`fab_for`), on wider
/// screens a filled button in the app bar (`app_bar_for`). The page describes it once; CSS shows the one that fits.
pub type Main(msg) {
  Main(symbol: Icon, label: String, msg: msg)
}

pub fn fab_for(main: Option(Main(msg))) -> Element(msg) {
  case main {
    Some(Main(symbol, label, msg)) ->
      fab([attribute.type_("button"), event.on_click(msg)], symbol, label)
    None -> element.none()
  }
}

pub fn app_bar_for(main: Option(Main(msg))) -> Element(msg) {
  case main {
    Some(Main(symbol, label, msg)) ->
      fluent(
        "primary",
        [
          attribute.class("bar-main-action"),
          attribute.type_("button"),
          event.on_click(msg),
        ],
        [icon.view(symbol), html.text(label)],
      )
    None -> element.none()
  }
}
