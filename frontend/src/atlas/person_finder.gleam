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
  Failed(String)
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
            status, _ -> #(
              Model(
                ..model,
                lookup: Failed(api.lookup_error(status, response.body)),
              ),
              [],
            )
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
      html.label([attribute.for(labels.field_id)], [
        html.text(labels.field_label),
      ]),
      html.div([class("row")], [
        field.input([
          attribute.id(labels.field_id),
          attribute.type_("email"),
          attribute.name("email"),
          attribute.autocomplete("off"),
          attribute.value(model.email),
          event.on_input(fn(text) { wrap(EmailChanged(text)) }),
        ]),
        button.filled(
          [
            attribute.type_("submit"),
            attribute.disabled(model.lookup == Looking),
          ],
          [
            html.text(case model.lookup {
              Looking -> "Looking…"
              _ -> "Find"
            }),
          ],
        ),
      ]),
      case model.lookup {
        Failed(message) -> error.message(message)
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
