//// Lustre element constructors for the Shoelace custom elements Atlas uses (ADR 0037).
//// Each one is `lustre/element.element` under the matching Shoelace tag, with no
//// behaviour of its own, mirroring `lustre/element/html`.

import lustre/attribute.{type Attribute}
import lustre/element.{type Element}

pub fn button(
  attributes: List(Attribute(msg)),
  children: List(Element(msg)),
) -> Element(msg) {
  element.element("sl-button", attributes, children)
}

pub fn input(attributes: List(Attribute(msg))) -> Element(msg) {
  element.element("sl-input", attributes, [])
}

pub fn textarea(attributes: List(Attribute(msg))) -> Element(msg) {
  element.element("sl-textarea", attributes, [])
}

pub fn select(
  attributes: List(Attribute(msg)),
  options: List(Element(msg)),
) -> Element(msg) {
  element.element("sl-select", attributes, options)
}

pub fn option(attributes: List(Attribute(msg)), label: String) -> Element(msg) {
  element.element("sl-option", attributes, [element.text(label)])
}
