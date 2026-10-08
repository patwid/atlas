//// Material 3 progress and loading indicators (ADR 0048, 0053).

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// M3 Expressive's loading indicator, a shape that morphs as it turns, with what is going on next to it, such as
/// "Copying…", for a wait of a few seconds. The text is the status screen readers announce; the shape is decorative.
pub fn loading(label: String) -> Element(msg) {
  html.p([class("loading"), attribute.role("status")], [
    html.span(
      [
        class("md-loading-indicator"),
        attribute.attribute("aria-hidden", "true"),
      ],
      [],
    ),
    html.text(label),
  ])
}
