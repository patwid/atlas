//// Finding a person by e-mail address and confirming them, before giving them something (ADR 0010, 0024, 0029).
//// Used where an athlete adds a coach and where an owner shares a plan. The state is `Model`; what
//// happens once the person is confirmed is up to the screen that embeds it. Pure apart from the
//// lookup request, which comes back as an `Action` for the app to send.

import atlas/api
import atlas/grants.{type Person}
import atlas/http
import atlas/ui/button
import atlas/ui/error
import atlas/ui/field
import atlas/ui/icon
import atlas/ui/layout
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Lookup {
  Idle
  Looking
  /// Found: the user has to confirm before anything is given.
  Found(Person)
  /// Something about the address typed: shown under the field, which is marked (ADR 0078).
  Failed(String)
  /// The lookup could not be made (offline, signed out, too many, the server): shown under the form.
  Unreachable(String)
}

pub type Model {
  Model(email: String, lookup: Lookup)
}

pub type Msg {
  EmailChanged(String)
  FindClicked
  LookupAnswered(http.Response)
  CancelClicked
}

pub type Action {
  /// Ask the server who has this e-mail address; the answer comes back as `LookupAnswered`.
  LookUp(email: String)
}

pub fn new() -> Model {
  Model("", Idle)
}

/// Clears the form, for after the person has been confirmed.
pub fn reset(_model: Model) -> Model {
  new()
}

/// The person found and waiting for confirmation, if any.
pub fn found(model: Model) -> Option(Person) {
  case model.lookup {
    Found(person) -> Some(person)
    _ -> None
  }
}

/// `me` is the signed-in user (they cannot pick themselves). `refuse` says whether a found person is not
/// acceptable, and why in a sentence that starts with their name or "This person" (for example "Bob already has access.").
pub fn update(
  model: Model,
  msg: Msg,
  me: Person,
  refuse: fn(Person) -> Option(String),
) -> #(Model, List(Action)) {
  case msg {
    EmailChanged(text) -> #(Model(email: text, lookup: Idle), [])

    FindClicked ->
      case string.trim(model.email), model.lookup {
        _, Looking -> #(model, [])
        "", _ -> #(
          Model(..model, lookup: Failed("Enter an e-mail address.")),
          [],
        )
        typed, _ ->
          case string.contains(typed, "@") {
            False -> #(
              Model(..model, lookup: Failed("Enter a complete e-mail address.")),
              [],
            )
            True -> #(Model(..model, lookup: Looking), [LookUp(typed)])
          }
      }

    LookupAnswered(response) ->
      case model.lookup {
        Looking ->
          case response.status, api.parse_lookup(response.body) {
            200, Ok(person) ->
              case person.id == me.id, refuse(person) {
                True, _ -> #(
                  Model(..model, lookup: Failed("That is your own address.")),
                  [],
                )
                False, Some(reason) -> #(
                  Model(..model, lookup: Failed(reason)),
                  [],
                )
                False, None -> #(Model(..model, lookup: Found(person)), [])
              }
            status, _ -> {
              let message = api.lookup_error(status, response.body)
              let lookup = case status {
                400 | 404 -> Failed(message)
                _ -> Unreachable(message)
              }
              #(Model(..model, lookup: lookup), [])
            }
          }
        // An answer for a search the user has since changed or cancelled.
        _ -> #(model, [])
      }

    CancelClicked -> #(Model(..model, lookup: Idle), [])
  }
}

/// How a person is called in a sentence.
pub fn display(person: Person) -> String {
  case string.trim(person.name) {
    "" -> "This person"
    name -> name
  }
}

/// Wording and element IDs, which differ between the places this is used.
pub type Labels {
  Labels(
    /// The `id` of the e-mail field (its label's `for`).
    field_id: String,
    form_class: String,
    field_label: String,
    /// The line under the field, until there is an error to show there.
    field_help: String,
    /// What is asked once someone is found, given the name: "Found Bob. Let them see your training?"
    question: fn(String) -> String,
    confirm_label: String,
  )
}

/// `wrap` turns the finder's messages into the embedding screen's; `confirm` is the screen's message for
/// "yes, this person".
pub fn view(
  model: Model,
  labels: Labels,
  wrap: fn(Msg) -> msg,
  confirm: msg,
) -> Element(msg) {
  html.form(
    [class(labels.form_class), event.on_submit(fn(_) { wrap(FindClicked) })],
    [
      // The search is the field's own button, at its end, so the field has the width to itself and the button
      // that confirms someone is the one filled button (ADR 0083).
      field.with_trigger(
        field.text(
          labels.field_id,
          labels.field_label,
          case model.lookup {
            Failed(message) -> field.Help(..field.plain, error: Some(message))
            _ -> field.help(labels.field_help)
          },
          [
            attribute.type_("email"),
            attribute.name("email"),
            attribute.autocomplete("off"),
            attribute.value(model.email),
            event.on_input(fn(text) { wrap(EmailChanged(text)) }),
          ],
        ),
        case model.lookup {
          Looking ->
            button.button(
              [
                attribute.type_("submit"),
                class("md-icon-button field-trigger"),
                attribute.attribute("aria-label", "Looking…"),
                attribute.disabled(True),
              ],
              [
                html.span(
                  [
                    class("md-loading-indicator"),
                    attribute.attribute("aria-hidden", "true"),
                  ],
                  [],
                ),
              ],
            )
          _ ->
            button.icon(
              [attribute.type_("submit"), class("field-trigger")],
              icon.Search,
              "Find",
            )
        },
      ),
      case model.lookup {
        Unreachable(message) -> error.message(message)
        Found(person) ->
          html.div([class("found"), attribute.role("status")], [
            html.p([], [html.text(labels.question(display(person)))]),
            layout.actions([
              button.filled(
                [attribute.type_("button"), event.on_click(confirm)],
                [html.text(labels.confirm_label)],
              ),
              button.outlined(
                [attribute.type_("button"), event.on_click(wrap(CancelClicked))],
                [html.text("Cancel")],
              ),
            ]),
          ])
        _ -> element.none()
      },
    ],
  )
}
