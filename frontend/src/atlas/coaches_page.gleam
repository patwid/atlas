//// Coach access, in Settings: who may see the user's training, and whose training the user may see.
//// The athlete gives access: look a person up by e-mail, confirm, and a grant is created that carries
//// both names (ADR 0010, 0024). Own state and messages; writes and the lookup come back as `Action`s.

import atlas/collection
import atlas/grants.{type Grant, type Person}
import atlas/outbox
import atlas/person_finder
import atlas/random
import atlas/records
import atlas/route
import atlas/store
import atlas/ui/button
import atlas/ui/dialog
import atlas/ui/layout
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model(
    grants: List(Grant),
    loaded: Bool,
    /// The form for adding a coach.
    finder: person_finder.Model,
    /// The grant whose "Remove access" was clicked once.
    confirming: Option(String),
  )
}

pub type Msg {
  Refresh
  GrantsRead(Result(List(Dynamic), Nil))
  Finder(person_finder.Msg)
  GiveAccessClicked
  CancelClicked
  RemoveClicked(String)
  RemoveConfirmed(String)
}

pub type Action {
  /// Ask the server who has this e-mail address; the answer comes back as `Finder(LookupAnswered(..))`.
  LookUp(email: String)
  Grant(id: String, fields: outbox.Fields)
  Revoke(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model([], False, person_finder.new(), None)
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

    Finder(inner) -> {
      let refuse = fn(person: Person) {
        case grants.has_grant(model.grants, me.id, person.id) {
          True -> Some(person_finder.display(person) <> " already has access.")
          False -> None
        }
      }
      let #(finder, found) =
        person_finder.update(model.finder, inner, me, refuse)
      #(
        Model(..model, finder: finder),
        effect.none(),
        list.map(found, fn(action) {
          let person_finder.LookUp(email) = action
          LookUp(email)
        }),
      )
    }

    GiveAccessClicked ->
      case person_finder.found(model.finder) {
        Some(person) -> #(
          Model(..model, finder: person_finder.reset(model.finder)),
          effect.none(),
          [Grant(random.new_id(), grant_fields(me, person))],
        )
        None -> #(model, effect.none(), [])
      }

    CancelClicked -> #(Model(..model, confirming: None), effect.none(), [])

    RemoveClicked(id) -> #(
      Model(..model, confirming: Some(id)),
      dialog.show(confirm_dialog_id(id)),
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
      True, _ -> layout.cards(list.map(given, given_view))
    },
    person_finder.view(
      model.finder,
      person_finder.Labels(
        field_id: "coach-email",
        form_class: "coach-form",
        field_label: "Add a coach by e-mail address",
        question: fn(name) {
          "Found " <> name <> ". Let them see your training?"
        },
        confirm_label: "Give access",
      ),
      Finder,
      GiveAccessClicked,
    ),
    case athletes {
      [] -> element.none()
      people ->
        html.div([], [
          html.h2([], [html.text("Athletes you coach")]),
          layout.cards(
            list.map(people, fn(p) {
              html.li([], [
                html.a([attribute.href(route.to_path(route.Athlete(p.id)))], [
                  html.text(p.name),
                ]),
              ])
            }),
          ),
        ])
    },
  ])
}

fn confirm_dialog_id(id: String) -> String {
  "confirm-remove-coach-" <> id
}

fn given_view(g: Grant) -> Element(Msg) {
  html.li([], [
    html.strong([], [
      html.text(case g.coach_name {
        "" -> "Unnamed coach"
        name -> name
      }),
    ]),
    layout.actions([
      button.outlined(
        [attribute.type_("button"), event.on_click(RemoveClicked(g.id))],
        [html.text("Remove access")],
      ),
      dialog.view(
        confirm_dialog_id(g.id),
        "Stop "
          <> case g.coach_name {
          "" -> "this coach"
          name -> name
        }
          <> " from seeing your training?",
        CancelClicked,
        [
          button.text(
            [attribute.type_("submit"), event.on_click(CancelClicked)],
            [html.text("Keep it")],
          ),
          button.text(
            [attribute.type_("submit"), event.on_click(RemoveConfirmed(g.id))],
            [html.text("Yes, remove access")],
          ),
        ],
      ),
    ]),
  ])
}
