//// Small typed wrappers over Atlas's own form-control styling (ADR 0040), so call sites don't
//// repeat the `"form-control"`/`"form-select"` CSS class by hand. Named `field`, not `form`,
//// because `form` is already the usual parameter name for a page's form data (e.g.
//// `plan_form.Form`), which would shadow a module of that name.

import gleam/list
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

/// `options` are `#(value, label)` pairs. The current value is marked `selected` on its option
/// rather than set as the `<select>`'s `value`: the virtual DOM sets attributes before it adds the
/// children, so a `value` on the `<select>` itself finds no matching option yet and the first
/// option shows instead.
pub fn select(
  attributes: List(Attribute(msg)),
  value: String,
  options: List(#(String, String)),
) -> Element(msg) {
  html.select(
    [class("form-select"), ..attributes],
    list.map(options, fn(option) {
      html.option(
        [attribute.value(option.0), attribute.selected(option.0 == value)],
        option.1,
      )
    }),
  )
}
