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

import atlas/ui/icon.{type Icon}
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
  let supporting_id = id <> "-supporting"
  // Fluent UI's alert dialog (ADR 0124, 0133 spike): it asks before something that cannot be taken back, so a click
  // outside does not close it. The native `<dialog>` is in its shadow root; `show` opens it, and Fluent reports any
  // way it closes as a `toggle` to "closed".
  element.element(
    "fluent-dialog",
    [
      attribute.id(id),
      attribute.attribute("type", "alert"),
      // Fluent passes ARIA on to the `<dialog>` in its shadow root, where an id from the page cannot be found, so the
      // name is given as text. The sentence is not read out with it: Fluent passes on no text form of a description.
      attribute.aria_label(label),
      event.on("toggle", {
        use state <- decode.subfield(["detail", "newState"], decode.string)
        case state {
          "closed" -> decode.success(on_hide)
          _ -> decode.failure(on_hide, "a dialog closing")
        }
      }),
    ],
    [
      element.element("fluent-dialog-body", [], [
        html.h2(
          [
            attribute.id(label_id),
            attribute.class("dialog-headline"),
            attribute.attribute("slot", "title"),
          ],
          [html.text(label)],
        ),
        html.p(
          [attribute.id(supporting_id), attribute.class("dialog-supporting")],
          [html.text(supporting)],
        ),
        // A form with method="dialog" closes the `<dialog>` it is in, but here that one is in the shadow root, out of
        // its reach: `show` closes the dialog on the form's submit instead.
        html.form(
          [
            attribute.attribute("method", "dialog"),
            attribute.class("actions"),
            attribute.attribute("slot", "action"),
          ],
          footer,
        ),
      ]),
    ],
  )
}

/// M3's simple dialog (ADR 0062): a headline and a list of `choices`, one of which is taken at once. It opens when
/// drawn (`data-open`, see `atlas/ui/interaction`); Escape, a click outside and a submit button in `actions` send
/// `on_close`. `body` is the list, or a sentence when there is nothing to choose.
pub fn simple(
  id: String,
  headline: String,
  on_close: msg,
  body: Element(msg),
  actions: List(Element(msg)),
) -> Element(msg) {
  let headline_id = id <> "-headline"
  html.dialog(
    [
      attribute.id(id),
      attribute.class("choice-dialog"),
      attribute.attribute("data-open", "true"),
      attribute.attribute("aria-labelledby", headline_id),
      event.on("close", decode.success(on_close)),
    ],
    [
      html.h2([attribute.class("dialog-headline"), attribute.id(headline_id)], [
        html.text(headline),
      ]),
      body,
      html.form(
        [attribute.attribute("method", "dialog"), attribute.class("actions")],
        actions,
      ),
    ],
  )
}

/// The choices of a `simple` dialog.
pub fn choices(items: List(Element(msg))) -> Element(msg) {
  html.ul([attribute.class("choices")], items)
}

/// One of a `simple` dialog's `choices`: an icon and what it is.
pub fn choice(symbol: Icon, label: String, on_click: msg) -> Element(msg) {
  html.li([], [
    html.button(
      [
        attribute.type_("button"),
        attribute.class("choice-row"),
        event.on_click(on_click),
      ],
      [icon.view(symbol), html.text(label)],
    ),
  ])
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
