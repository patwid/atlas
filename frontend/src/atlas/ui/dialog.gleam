//// Atlas's dialogs, drawn as Fluent UI's (ADR 0040, 0133): confirmations (`view`), simple dialogs of choices
//// (`simple`) and details (`details`). A dialog can't be driven by attributes alone: its `show()` must be called. For
//// a confirmation `show` does that, as an `Effect` run the moment a page's `Model` moves into "confirming"; the
//// others say with `data-open` whether they should show, and `atlas/ui/interaction` keeps them in step.
////
//// Once open, Escape, a click outside (except on a confirmation) or a submit button in the dialog's
//// `<form method="dialog">` close it, and each sends the dialog's close message, so the page's `Model` and the
//// dialog's actual state can't drift apart, however it was closed.

import atlas/ui/button
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
  // An alert dialog (ADR 0124): it asks before something that cannot be taken back, so a click outside does not close
  // it. Its sentence is not read out with the headline: see `fluent`.
  fluent(
    id,
    "alert",
    label,
    [],
    on_hide,
    [
      html.p(
        [
          attribute.id(id <> "-supporting"),
          attribute.class("dialog-supporting"),
        ],
        [
          html.text(supporting),
        ],
      ),
    ],
    footer,
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
  fluent(
    id,
    "modal",
    headline,
    [
      attribute.class("choice-dialog"),
      attribute.attribute("data-open", "true"),
    ],
    on_close,
    [body],
    actions,
  )
}

/// The choices of a `simple` dialog.
pub fn choices(items: List(Element(msg))) -> Element(msg) {
  html.ul([attribute.class("choices")], items)
}

/// One of a `simple` dialog's `choices`: an icon and what it is. Fluent has no list, so a row is a native button.
pub fn choice(symbol: Icon, label: String, on_click: msg) -> Element(msg) {
  html.li([], [
    button.button(
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
  let data_open =
    attribute.attribute("data-open", case open {
      True -> "true"
      False -> "false"
    })
  case open {
    False ->
      element.element(
        "fluent-dialog",
        [
          attribute.id(id),
          attribute.class("details-dialog"),
          data_open,
          on_closed(on_close),
        ],
        [],
      )
    True ->
      fluent(
        id,
        "modal",
        headline,
        [attribute.class("details-dialog"), data_open],
        on_close,
        [html.div([attribute.class("details-body")], body)],
        list.append(actions, [
          button.text([attribute.type_("submit")], [html.text("Close")]),
        ]),
      )
  }
}

/// Fluent UI's dialog (ADR 0133) of a `kind`: "alert", which only its buttons and Escape close, or "modal", which a
/// click outside also closes. The native `<dialog>` is in its shadow root, so:
///
/// - Fluent passes ARIA on to that `<dialog>`, where an id from the page cannot be found: the dialog is named by its
///   `headline` as text, and nothing describes it.
/// - A form with method="dialog" cannot close it from outside: `atlas/ui/dialog.ffi.mjs` and `atlas/ui/interaction`
///   close it on the form's submit.
/// - It reports any way it closes as a `toggle` to "closed", which sends `on_close`.
///
/// The headline keeps an id (`id-headline`), so a test can tell whether the content is drawn.
fn fluent(
  id: String,
  kind: String,
  headline: String,
  attributes: List(attribute.Attribute(msg)),
  on_close: msg,
  content: List(Element(msg)),
  actions: List(Element(msg)),
) -> Element(msg) {
  element.element(
    "fluent-dialog",
    [
      attribute.id(id),
      attribute.attribute("type", kind),
      attribute.aria_label(headline),
      on_closed(on_close),
      ..attributes
    ],
    [
      element.element("fluent-dialog-body", [], [
        html.h2(
          [
            attribute.id(id <> "-headline"),
            attribute.class("dialog-headline"),
            attribute.attribute("slot", "title"),
          ],
          [html.text(headline)],
        ),
        ..list.append(content, [
          html.form(
            [
              attribute.attribute("method", "dialog"),
              attribute.class("actions"),
              attribute.attribute("slot", "action"),
            ],
            actions,
          ),
        ])
      ]),
    ],
  )
}

fn on_closed(message: msg) -> attribute.Attribute(msg) {
  event.on("toggle", {
    use state <- decode.subfield(["detail", "newState"], decode.string)
    case state {
      "closed" -> decode.success(message)
      _ -> decode.failure(message, "a dialog closing")
    }
  })
}
