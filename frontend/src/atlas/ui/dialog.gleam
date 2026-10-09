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
import gleam/list
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
/// `label` is the short question, shown as the dialog's headline ("Delete workout?"); `supporting` says what
/// happens, in a sentence (ADR 0055); `on_hide` fires whenever the dialog is asked to close, for any reason;
/// `footer` are the dialog's action buttons, named by what they do ("Cancel", "Delete"), the dismissive one first.
pub fn view(
  id: String,
  label: String,
  supporting: String,
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
      html.p([attribute.id(label_id), attribute.class("dialog-headline")], [
        html.text(label),
      ]),
      html.p([attribute.class("dialog-supporting")], [html.text(supporting)]),
      html.form(
        [attribute.attribute("method", "dialog"), attribute.class("actions")],
        footer,
      ),
    ],
  )
}

/// A basic dialog that shows something, such as a workout or a week (ADR 0066): a headline, the content, the
/// `actions` and Close. Like the form dialogs it is declarative: `open` says whether it shows, and
/// `atlas/ui/interaction` opens or closes it to match (`data-open`). Escape, a click outside and Close send `on_close`.
pub fn details(
  id: String,
  open: Bool,
  headline: String,
  on_close: msg,
  body: List(Element(msg)),
  actions: List(Element(msg)),
) -> Element(msg) {
  let headline_id = id <> "-headline"
  html.dialog(
    [
      attribute.id(id),
      attribute.class("details-dialog"),
      attribute.attribute("data-open", case open {
        True -> "true"
        False -> "false"
      }),
      attribute.attribute("aria-labelledby", headline_id),
      event.on("close", decode.success(on_close)),
    ],
    case open {
      False -> []
      True -> [
        html.h2(
          [attribute.id(headline_id), attribute.class("dialog-headline")],
          [
            html.text(headline),
          ],
        ),
        html.div([attribute.class("details-body")], body),
        html.form(
          [attribute.attribute("method", "dialog"), attribute.class("actions")],
          list.append(actions, [
            html.button(
              [
                attribute.type_("submit"),
                attribute.class("md-button md-button-text"),
              ],
              [html.text("Close")],
            ),
          ]),
        ),
      ]
    },
  )
}
