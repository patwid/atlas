//// A form's validation error message (ADR 0040): collapses the `class("error")` +
//// `attribute.role("alert")` pairing repeated at every form. Forgetting the role would still
//// show the message, but silently stop a screen reader from announcing it.

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

pub fn message(text: String) -> Element(msg) {
  html.p([class("error"), attribute.role("alert")], [html.text(text)])
}
