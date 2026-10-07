//// Sharing a plan with named people, on the owner's plan screen: who has it, "Stop sharing", and adding a
//// person found by e-mail address after confirmation (ADR 0029). Own state and messages; writes and the
//// lookup come back as `Action`s.

import atlas/collection
import atlas/grants.{type Person}
import atlas/outbox
import atlas/person_finder
import atlas/random
import atlas/records
import atlas/shares.{type Share}
import atlas/store
import atlas/ui/html as sl
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
    /// Every share on the device, removed ones included.
    shares: List(Share),
    loaded: Bool,
    finder: person_finder.Model,
    /// The share whose "Stop sharing" was clicked once.
    confirming: Option(String),
  )
}

/// What the screen needs to know that is not its own state: the plan on screen and who is looking.
pub type Context {
  Context(plan_id: String, me: Person, is_owner: Bool)
}

pub type Msg {
  Refresh
  SharesRead(Result(List(Dynamic), Nil))
  Finder(person_finder.Msg)
  ShareClicked
  StopClicked(String)
  StopConfirmed(String)
  CancelClicked
}

pub type Action {
  LookUp(email: String)
  /// A new share row.
  Share(id: String, fields: outbox.Fields)
  /// Sharing again with someone it was shared with before: their old row is made live again.
  ShareAgain(id: String, fields: outbox.Fields, base_updated: String)
  Stop(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model([], False, person_finder.new(), None)
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.PlanShares, fn(result) {
      dispatch(SharesRead(result))
    })
  })
}

pub fn update(
  model: Model,
  msg: Msg,
  context: Context,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    SharesRead(Ok(stored)) -> #(
      Model(
        ..model,
        shares: list.filter_map(stored, records.share),
        loaded: True,
      ),
      effect.none(),
      [],
    )
    SharesRead(Error(Nil)) -> #(model, effect.none(), [])

    // Only the owner shares; for anyone else nothing happens.
    _ if !context.is_owner -> #(model, effect.none(), [])

    Finder(inner) -> {
      let refuse = fn(person: Person) {
        case shares.is_shared_with(model.shares, context.plan_id, person.id) {
          True ->
            Some(person_finder.display(person) <> " already has this plan.")
          False -> None
        }
      }
      let #(finder, found) =
        person_finder.update(model.finder, inner, context.me, refuse)
      #(
        Model(..model, finder: finder),
        effect.none(),
        list.map(found, fn(action) {
          let person_finder.LookUp(email) = action
          LookUp(email)
        }),
      )
    }

    ShareClicked ->
      case person_finder.found(model.finder) {
        None -> #(model, effect.none(), [])
        Some(person) -> #(
          Model(..model, finder: person_finder.reset(model.finder)),
          effect.none(),
          [share_action(model, context, person)],
        )
      }

    StopClicked(id) -> #(
      Model(..model, confirming: Some(id)),
      effect.none(),
      [],
    )

    StopConfirmed(id) ->
      case
        list.find(model.shares, fn(s) {
          s.id == id && s.plan_id == context.plan_id && !s.deleted
        })
      {
        Ok(found) -> #(Model(..model, confirming: None), effect.none(), [
          Stop(id, found.updated),
        ])
        Error(Nil) -> #(model, effect.none(), [])
      }

    CancelClicked -> #(Model(..model, confirming: None), effect.none(), [])
  }
}

fn share_action(model: Model, context: Context, person: Person) -> Action {
  let labels = [
    outbox.field_string("user_name", person.name),
    outbox.field_string("shared_by_name", context.me.name),
  ]
  case shares.row_for(model.shares, context.plan_id, person.id) {
    Some(old) ->
      ShareAgain(
        old.id,
        dict.from_list([outbox.field_bool("deleted", False), ..labels]),
        old.updated,
      )
    None ->
      Share(
        random.new_id(),
        dict.from_list([
          outbox.field_string("plan", context.plan_id),
          outbox.field_string("user", person.id),
          ..labels
        ]),
      )
  }
}

// VIEWS -------------------------------------------------------------------------------------------

/// Shown to the owner of the plan only.
pub fn view(model: Model, context: Context) -> Element(Msg) {
  let current = shares.current_for(model.shares, context.plan_id)
  html.section([class("sharing")], [
    html.h2([], [html.text("Sharing")]),
    html.p([class("muted")], [
      html.text(
        "People you share this plan with can read it, copy it and start it. They cannot change it.",
      ),
    ]),
    case model.loaded, current {
      False, _ -> html.p([class("muted")], [html.text("Loading…")])
      True, [] ->
        html.p([class("muted")], [html.text("Not shared with anyone.")])
      True, _ ->
        html.ul(
          [class("cards")],
          list.map(current, fn(share) { share_view(share, model) }),
        )
    },
    person_finder.view(
      model.finder,
      person_finder.Labels(
        field_id: "share-email",
        form_class: "share-form",
        field_label: "Share with someone by e-mail address",
        question: fn(name) {
          "Found " <> name <> ". Share this plan with them?"
        },
        confirm_label: "Share plan",
      ),
      Finder,
      ShareClicked,
    ),
  ])
}

fn share_view(share: Share, model: Model) -> Element(Msg) {
  let name = case share.user_name {
    "" -> "Unnamed person"
    named -> named
  }
  html.li([], [
    html.strong([], [html.text(name)]),
    html.div([class("actions")], case model.confirming == Some(share.id) {
      False -> [
        sl.button(
          [
            attribute.type_("button"),
            attribute.attribute("variant", "default"),
            event.on_click(StopClicked(share.id)),
          ],
          [html.text("Stop sharing")],
        ),
      ]
      True -> [
        html.span([attribute.role("alert")], [
          html.text("Stop sharing this plan with " <> name <> "?"),
        ]),
        sl.button(
          [
            attribute.type_("button"),
            attribute.attribute("variant", "danger"),
            event.on_click(StopConfirmed(share.id)),
          ],
          [html.text("Yes, stop sharing")],
        ),
        sl.button(
          [
            attribute.type_("button"),
            attribute.attribute("variant", "default"),
            event.on_click(CancelClicked),
          ],
          [html.text("Keep sharing")],
        ),
      ]
    }),
  ])
}
