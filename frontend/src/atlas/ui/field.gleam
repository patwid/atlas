//// Small typed wrappers over Atlas's own form-control styling (ADR 0040), so call sites don't
//// repeat the `"form-control"`/`"form-select"` CSS class by hand. Named `field`, not `form`,
//// because `form` is already the usual parameter name for a page's form data (e.g.
//// `plan_form.Form`), which would shadow a module of that name.

import lustre/attribute.{type Attribute, class}
import lustre/element.{type Element}
import lustre/element/html

pub fn input(attributes: List(Attribute(msg))) -> Element(msg) {
  html.input([class("form-control"), ..attributes])
}

pub fn textarea(
  attributes: List(Attribute(msg)),
  content: String,
) -> Element(msg) {
  html.textarea([class("form-control"), ..attributes], content)
}

pub fn select(
  attributes: List(Attribute(msg)),
  options: List(Element(msg)),
) -> Element(msg) {
  html.select([class("form-select"), ..attributes], options)
}
