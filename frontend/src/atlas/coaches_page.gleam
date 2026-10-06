//// Coach access, in Settings: who may see the user's training, and whose training the user may see.
//// The athlete gives access: look a person up by e-mail, confirm, and a grant is created that carries
//// both names (ADR 0010, 0024). Own state and messages; writes and the lookup come back as `Action`s.

import atlas/api
import atlas/collection
import atlas/grants.{type Grant, type Person}
import atlas/http
import atlas/outbox
import atlas/random
import atlas/records
import atlas/store
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Lookup {
  Idle
  Looking
  /// Found: the user has to confirm before access is given.
  Found(Person)
  Failed(String)
}

pub type Model {
  Model(
    grants: List(Grant),
    loaded: Bool,
    email: String,
    lookup: Lookup,
    /// The grant whose "Remove access" was clicked once.
    confirming: Option(String),
  )
}

pub type Msg {
  Refresh
  GrantsRead(Result(List(Dynamic), Nil))
  EmailChanged(String)
  FindClicked
  LookupAnswered(http.Response)
  GiveAccessClicked
  CancelClicked
  RemoveClicked(String)
  RemoveConfirmed(String)
}

pub type Action {
  /// Ask the server who has this e-mail address; the answer comes back as `LookupAnswered`.
  LookUp(email: String)
  Grant(id: String, fields: outbox.Fields)
  Revoke(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model([], False, "", Idle, None)
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.CoachGrants, fn(result) {
      dispatch(GrantsRead(result))
    })
  })
}

/// `me` is the signed-in user, whose name goes on the grants they make.
pub fn update(
  model: Model,
  msg: Msg,
  me: Person,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    GrantsRead(Ok(stored)) -> #(
      Model(..model, grants: records.live(stored, records.grant), loaded: True),
      effect.none(),
      [],
    )
    GrantsRead(Error(Nil)) -> #(model, effect.none(), [])

    EmailChanged(text) -> #(
      Model(..model, email: text, lookup: Idle),
      effect.none(),
      [],
    )

    FindClicked ->
      case string.trim(model.email), model.lookup {
        _, Looking -> #(model, effect.none(), [])
        "", _ -> #(
          Model(..model, lookup: Failed("Enter an e-mail address.")),
          effect.none(),
          [],
        )
        typed, _ ->
          case string.contains(typed, "@") {
            False -> #(
              Model(..model, lookup: Failed("Enter a complete e-mail address.")),
              effect.none(),
              [],
            )
            True -> #(Model(..model, lookup: Looking), effect.none(), [
              LookUp(typed),
            ])
          }
      }

    LookupAnswered(response) ->
      case model.lookup {
        Looking ->
          case response.status, api.parse_lookup(response.body) {
            200, Ok(person) ->
              case person.id == me.id {
                True -> #(
                  Model(..model, lookup: Failed("That is your own address.")),
                  effect.none(),
                  [],
                )
                False ->
                  case grants.has_grant(model.grants, me.id, person.id) {
                    True -> #(
                      Model(
                        ..model,
                        lookup: Failed(
                          display(person) <> " already has access.",
                        ),
                      ),
                      effect.none(),
                      [],
                    )
                    False -> #(
                      Model(..model, lookup: Found(person)),
                      effect.none(),
                      [],
                    )
                  }
              }
            status, _ -> #(
              Model(
                ..model,
                lookup: Failed(api.lookup_error(status, response.body)),
              ),
              effect.none(),
              [],
            )
          }
        // An answer for a search the user has since changed or cancelled.
        _ -> #(model, effect.none(), [])
      }

    GiveAccessClicked ->
      case model.lookup {
        Found(person) -> #(
          Model(..model, email: "", lookup: Idle),
          effect.none(),
          [Grant(random.new_id(), grant_fields(me, person))],
        )
        _ -> #(model, effect.none(), [])
      }

    CancelClicked -> #(
      Model(..model, lookup: Idle, confirming: None),
      effect.none(),
      [],
    )

    RemoveClicked(id) -> #(
      Model(..model, confirming: Some(id)),
      effect.none(),
      [],
    )

    RemoveConfirmed(id) ->
      case
        list.find(model.grants, fn(g) { g.id == id && g.athlete_id == me.id })
      {
        Ok(found) -> #(Model(..model, confirming: None), effect.none(), [
          Revoke(id, found.updated),
        ])
        // Only the athlete can take access back, and only grants they gave.
        Error(Nil) -> #(model, effect.none(), [])
      }
  }
}

fn grant_fields(me: Person, coach: Person) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("athlete", me.id),
    outbox.field_string("coach", coach.id),
    outbox.field_string("athlete_name", me.name),
    outbox.field_string("coach_name", coach.name),
  ])
}

fn display(person: Person) -> String {
  case string.trim(person.name) {
    "" -> "This person"
    name -> name
  }
}

// VIEWS -------------------------------------------------------------------------------------------

pub fn view(model: Model, me: String) -> Element(Msg) {
  let given = grants.given_by(model.grants, me)
  let athletes = grants.athletes_of(model.grants, me)
  html.section([class("coaches")], [
    html.h2([], [html.text("Coaches")]),
    html.p([class("muted")], [
      html.text(
        "A coach can see your plans, activities and progress, and can give you plans to follow.",
      ),
    ]),
    case model.loaded, given {
      False, _ -> html.p([class("muted")], [html.text("Loading…")])
      True, [] ->
        html.p([class("muted")], [html.text("Nobody can see your training.")])
      True, _ ->
        html.ul(
          [class("cards")],
          list.map(given, fn(g) { given_view(g, model) }),
        )
    },
    add_view(model),
    case athletes {
      [] -> element.none()
      people ->
        html.div([], [
          html.h2([], [html.text("Athletes you coach")]),
          html.ul(
            [class("cards")],
            list.map(people, fn(p) { html.li([], [html.text(p.name)]) }),
          ),
        ])
    },
  ])
}

fn given_view(g: Grant, model: Model) -> Element(Msg) {
  html.li([], [
    html.strong([], [
      html.text(case g.coach_name {
        "" -> "Unnamed coach"
        name -> name
      }),
    ]),
    html.div([class("actions")], case model.confirming == Some(g.id) {
      False -> [
        html.button(
          [
            attribute.type_("button"),
            class("secondary"),
            event.on_click(RemoveClicked(g.id)),
          ],
          [html.text("Remove access")],
        ),
      ]
      True -> [
        html.span([attribute.role("alert")], [
          html.text(
            "Stop "
            <> case g.coach_name {
              "" -> "this coach"
              name -> name
            }
            <> " from seeing your training?",
          ),
        ]),
        html.button(
          [
            attribute.type_("button"),
            class("danger"),
            event.on_click(RemoveConfirmed(g.id)),
          ],
          [html.text("Yes, remove access")],
        ),
        html.button(
          [
            attribute.type_("button"),
            class("secondary"),
            event.on_click(CancelClicked),
          ],
          [html.text("Keep it")],
        ),
      ]
    }),
  ])
}

fn add_view(model: Model) -> Element(Msg) {
  html.form([class("coach-form"), event.on_submit(fn(_) { FindClicked })], [
    html.label([attribute.for("coach-email")], [
      html.text("Add a coach by e-mail address"),
    ]),
    html.div([class("row")], [
      html.input([
        attribute.id("coach-email"),
        attribute.type_("email"),
        attribute.name("email"),
        attribute.autocomplete("off"),
        attribute.value(model.email),
        event.on_input(EmailChanged),
      ]),
      html.button(
        [attribute.type_("submit"), attribute.disabled(model.lookup == Looking)],
        [
          html.text(case model.lookup {
            Looking -> "Looking…"
            _ -> "Find"
          }),
        ],
      ),
    ]),
    case model.lookup {
      Failed(message) ->
        html.p([class("error"), attribute.role("alert")], [html.text(message)])
      Found(person) ->
        html.div([class("found"), attribute.role("status")], [
          html.p([], [
            html.text(
              "Found " <> display(person) <> ". Let them see your training?",
            ),
          ]),
          html.div([class("actions")], [
            html.button(
              [attribute.type_("button"), event.on_click(GiveAccessClicked)],
              [html.text("Give access")],
            ),
            html.button(
              [
                attribute.type_("button"),
                class("secondary"),
                event.on_click(CancelClicked),
              ],
              [html.text("Cancel")],
            ),
          ]),
        ])
      _ -> element.none()
    },
  ])
}
