//// A form in a Material 3 full-screen dialog (ADR 0057): on a phone it fills the screen with a top bar holding
//// Close, the title and the form's submit button; on wider screens it is a basic dialog in the middle, with its
//// headline at the top and Cancel and a filled submit button at the bottom (ADR 0085). Both sets of buttons are
//// drawn and CSS shows the ones that fit, as for a screen's main action (ADR 0068). Create and edit
//// forms open here instead of inside the list, so the form is where the eye is, wherever the button was.
////
//// It is declarative: `open` says whether it shows, and `atlas/ui/interaction` opens or closes the native modal
//// `<dialog>` to match, so pages need no effect to open or close it. Escape and Close fire the dialog's `close`
//// event, which sends `on_close`. A click outside does not close it: that would throw away what was typed.

import atlas/ui/button
import atlas/ui/icon
import gleam/dynamic/decode
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// `form_id` is the `id` of the `<form>` in `body`, which the top bar's submit button belongs to; `body` is drawn
/// only while open.
pub fn view(
  id: String,
  open: Bool,
  title: String,
  form_id: String,
  submit_label: String,
  on_close: msg,
  body: List(Element(msg)),
) -> Element(msg) {
  view_with_action(
    id,
    open,
    title,
    form_id,
    submit_label,
    on_close,
    element.none(),
    body,
  )
}

/// `view` with an icon button in the top bar before the submit button, such as Delete when editing (ADR 0080).
pub fn view_with_action(
  id: String,
  open: Bool,
  title: String,
  form_id: String,
  submit_label: String,
  on_close: msg,
  action: Element(msg),
  body: List(Element(msg)),
) -> Element(msg) {
  let title_id = id <> "-title"
  html.dialog(
    [
      attribute.id(id),
      class("form-dialog"),
      attribute.attribute("data-open", case open {
        True -> "true"
        False -> "false"
      }),
      attribute.attribute("aria-labelledby", title_id),
      event.on("close", decode.success(on_close)),
    ],
    case open {
      False -> []
      True -> [
        html.div([class("form-dialog-bar")], [
          html.form(
            [
              class("form-dialog-close"),
              attribute.attribute("method", "dialog"),
            ],
            [button.icon([attribute.type_("submit")], icon.Close, "Cancel")],
          ),
          html.h2([attribute.id(title_id)], [html.text(title)]),
          action,
          button.text(
            [
              class("form-dialog-submit"),
              attribute.type_("submit"),
              attribute.attribute("form", form_id),
            ],
            [html.text(submit_label)],
          ),
        ]),
        html.div([class("form-dialog-body")], body),
        html.form(
          [
            class("actions form-dialog-actions"),
            attribute.attribute("method", "dialog"),
          ],
          [
            button.text([attribute.type_("submit")], [html.text("Cancel")]),
            button.filled(
              [attribute.type_("submit"), attribute.attribute("form", form_id)],
              [html.text(submit_label)],
            ),
          ],
        ),
      ]
    },
  )
}
