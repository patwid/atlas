//// Lustre element constructors for the Web Awesome custom elements Atlas uses (ADR 0038, 0039).
//// Each one is `lustre/element.element` under the matching Web Awesome tag, with no
//// behaviour of its own, mirroring `lustre/element/html`.
////
//// `input` and `textarea` take their value through `attribute.property`, not
//// `attribute.value`: Web Awesome's `value` *attribute* only sets the control's
//// `defaultValue` (used for form resets), and stops being read at all once the user has
//// typed into the field once (unlike Shoelace, where `value` was a plain reflected
//// property). Setting the live `value` DOM property directly is the only way Lustre's
//// re-renders keep reaching the displayed text after that point — for example when the
//// same `wa-input` node is reused to edit a different record, or when a field is filled
//// programmatically (the zones form's "fill from" buttons).

import gleam/json
import lustre/attribute.{type Attribute}
import lustre/element.{type Element}

pub fn button(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  element.element("wa-button", attributes, children)
}

pub fn input(attributes: List(Attribute(msg))) -> Element(msg) {
  element.element("wa-input", attributes, [])
}

pub fn textarea(attributes: List(Attribute(msg))) -> Element(msg) {
  element.element("wa-textarea", attributes, [])
}

pub fn select(
  attributes: List(Attribute(msg)),
  options: List(Element(msg)),
) -> Element(msg) {
  element.element("wa-select", attributes, options)
}

pub fn option(attributes: List(Attribute(msg)), label: String) -> Element(msg) {
  element.element("wa-option", attributes, [element.text(label)])
}

pub fn dialog(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  element.element("wa-dialog", attributes, children)
}

/// Sets a `wa-input`/`wa-textarea`'s live value as a DOM property, not an attribute.
/// Use this in place of `lustre/attribute.value` for those two elements; see the module
/// comment above for why `attribute.value` alone isn't enough for them.
pub fn value(control_value: String) -> Attribute(msg) {
  attribute.property("value", json.string(control_value))
}
