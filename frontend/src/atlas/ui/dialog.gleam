//// A confirmation dialog backed by the native `<dialog>` element. Unlike Atlas's other form
//// controls, `<dialog>` can't be driven by attributes alone: `showModal()` must be called
//// imperatively to get a real modal (focus trap, Escape-to-cancel, a backdrop) rather than a
//// plain block-level element. `show` does that via a small FFI call, as an `Effect` run the
//// moment a page's `Model` moves into "confirming" (see ADR 0040).
////
//// Once open, the browser's own Escape key, a backdrop click (light-dismiss, wired in the FFI),
//// or any `<button>` inside the dialog's `<form method="dialog">` all close it natively and fire
//// the `close` event `on_hide` is wired to — so the page's `Model` and the dialog's actual state
//// can't drift apart, regardless of how it was closed.

import gleam/dynamic/decode
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

@external(javascript, "./dialog.ffi.mjs", "showModal")
fn do_show_modal(id: String) -> Nil

/// Opens the dialog with the given `id` as a real modal. Return this from `update` in the same
/// branch that sets the page's `Model` into "confirming".
pub fn show(id: String) -> Effect(msg) {
  effect.from(fn(_dispatch) { do_show_modal(id) })
}

/// `id` must be unique in the page (and stable across re-renders, so `show` can find it);
/// `label` is the confirmation question, shown as the dialog's heading; `on_hide` fires whenever
/// the dialog is asked to close, for any reason; `footer` are the dialog's action buttons.
pub fn view(
  id: String,
  label: String,
  on_hide: msg,
  footer: List(Element(msg)),
) -> Element(msg) {
  let label_id = id <> "-label"
  html.dialog(
    [
      attribute.id(id),
      attribute.attribute("aria-labelledby", label_id),
      event.on("close", decode.success(on_hide)),
    ],
    [
      html.p([attribute.id(label_id)], [html.text(label)]),
      html.form(
        [attribute.attribute("method", "dialog"), attribute.class("actions")],
        footer,
      ),
    ],
  )
}
