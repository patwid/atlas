//// Material 3 progress indicators (ADR 0048).

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// An indeterminate circular indicator with what is going on next to it, such as "Copying…". The text is the
/// status screen readers announce; the spinner is decorative.
pub fn circular(label: String) -> Element(msg) {
  html.p([class("loading"), attribute.role("status")], [
    html.span(
      [
        class("md-circular-progress"),
        attribute.attribute("aria-hidden", "true"),
      ],
      [],
    ),
    html.text(label),
  ])
}
