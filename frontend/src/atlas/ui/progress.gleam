//// Progress and loading indicators (ADR 0048), Fluent UI's (ADR 0133).

import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// Fluent's progress bar, indeterminate, for work going on in the background such as syncing. `label` names it for
/// screen readers.
pub fn linear(label: String) -> Element(msg) {
  element.element(
    "fluent-progress-bar",
    [class("linear-progress"), attribute.aria_label(label)],
    [],
  )
}

/// Fluent's spinner with what is going on next to it, such as "Copying…", for a wait of a few seconds. The text is
/// read out through the page's live region (`data-announce`, ADR 0124); the spinner is decorative.
pub fn loading(label: String) -> Element(msg) {
  html.p([class("loading"), attribute.attribute("data-announce", label)], [
    spinner(),
    html.text(label),
  ])
}

/// A small decorative spinner, such as in a button while it waits.
pub fn spinner() -> Element(msg) {
  element.element(
    "fluent-spinner",
    [
      attribute.attribute("size", "extra-small"),
      attribute.attribute("aria-hidden", "true"),
    ],
    [],
  )
}
