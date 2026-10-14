//// Goals, in Settings (ADR 0115): the athlete's race goals, any number of them, each a distance and the time to run
//// it in. A goal is added and edited in a form dialog and deleted from it, with Undo (ADR 0056, 0057, 0080). Own
//// state and messages; writes come back as `Action`s.

import atlas/collection
import atlas/goal.{type Goal}
import atlas/outbox
import atlas/random
import atlas/records
import atlas/store
import atlas/ui/button
import atlas/ui/empty
import atlas/ui/field
import atlas/ui/focus
import atlas/ui/form_dialog
import atlas/ui/icon
import atlas/ui/layout
import atlas/ui/progress
import atlas/ui/undo.{type Undo}
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
    goals: List(Goal),
    loaded: Bool,
    mode: Mode,
    form: goal.Form,
    error: Option(String),
    /// The ID of the input the error is about (ADR 0077).
    error_field: String,
    /// A delete that can still be undone (ADR 0056).
    undo: Undo,
  )
}

pub type Mode {
  Browsing
  Adding
  Editing(id: String)
}

pub type Msg {
  Refresh
  GoalsRead(Result(List(Dynamic), Nil))
  AddClicked
  EditClicked(String)
  CancelClicked
  DistanceChanged(String)
  TimeChanged(String)
  Submitted
  /// Deletes at once, with Undo for a few seconds (ADR 0056).
  DeleteClicked(String)
  UndoClicked
  DeleteExpired(Int)
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model([], False, Browsing, goal.empty_form(), None, "", undo.new())
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Goals, fn(result) { dispatch(GoalsRead(result)) })
  })
}

/// The goals of `me`, shortest first, without one whose delete is waiting.
pub fn mine(model: Model, me: String) -> List(Goal) {
  goal.of(model.goals, me)
  |> list.filter(fn(g) { !undo.hides(model.undo, g.id) })
}

/// `me` is the signed-in user, who owns their goals.
pub fn update(
  model: Model,
  msg: Msg,
  me: String,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    GoalsRead(Ok(stored)) -> #(
      Model(..model, goals: records.live(stored, records.goal), loaded: True),
      effect.none(),
      [],
    )
    GoalsRead(Error(Nil)) -> #(model, effect.none(), [])

    AddClicked -> #(
      Model(
        ..model,
        mode: Adding,
        form: goal.empty_form(),
        error: None,
        error_field: "",
      ),
      effect.none(),
      [],
    )

    EditClicked(id) ->
      case find(model, me, id) {
        Ok(found) -> #(
          Model(
            ..model,
            mode: Editing(id),
            form: goal.to_form(found),
            error: None,
            error_field: "",
          ),
          effect.none(),
          [],
        )
        Error(Nil) -> #(model, effect.none(), [])
      }

    CancelClicked -> #(Model(..model, mode: Browsing), effect.none(), [])

    DistanceChanged(value) -> #(
      Model(
        ..model,
        form: goal.Form(..model.form, distance_km: value),
        error: None,
        error_field: "",
      ),
      effect.none(),
      [],
    )

    TimeChanged(value) -> #(
      Model(
        ..model,
        form: goal.Form(..model.form, time: value),
        error: None,
        error_field: "",
      ),
      effect.none(),
      [],
    )

    Submitted ->
      case goal.parse(model.form) {
        Error(#(field_id, message)) -> #(
          Model(..model, error: Some(message), error_field: field_id),
          focus.soon(field_id),
          [],
        )
        Ok(#(distance_m, time_s)) -> {
          let fields = goal.fields(me, distance_m, time_s)
          let finished = Model(..model, mode: Browsing)
          case model.mode {
            Adding -> #(finished, effect.none(), [
              Create(random.new_id(), fields),
            ])
            Editing(id) ->
              case find(model, me, id) {
                Ok(found) -> #(finished, effect.none(), [
                  Edit(id, fields, found.updated),
                ])
                Error(Nil) -> #(finished, effect.none(), [])
              }
            Browsing -> #(model, effect.none(), [])
          }
        }
      }

    DeleteClicked(id) ->
      case find(model, me, id) {
        Error(Nil) -> #(model, effect.none(), [])
        Ok(_) -> {
          let #(next, earlier, wait) = undo.start(model.undo, id, DeleteExpired)
          #(
            Model(..model, undo: next, mode: Browsing),
            wait,
            option.map(earlier, delete_of(model, me, _)) |> option.unwrap([]),
          )
        }
      }

    UndoClicked -> #(
      Model(..model, undo: undo.cancel(model.undo)),
      effect.none(),
      [],
    )

    DeleteExpired(n) -> {
      let #(next, due) = undo.expire(model.undo, n)
      #(
        Model(..model, undo: next),
        effect.none(),
        option.map(due, delete_of(model, me, _)) |> option.unwrap([]),
      )
    }
  }
}

/// One of `me`'s own goals: only those can be changed.
fn find(model: Model, me: String, id: String) -> Result(Goal, Nil) {
  list.find(goal.of(model.goals, me), fn(g) { g.id == id })
}

fn delete_of(model: Model, me: String, id: String) -> List(Action) {
  case find(model, me, id) {
    Ok(found) -> [Delete(id, found.updated)]
    Error(Nil) -> []
  }
}

/// The screen's main action (ADR 0068).
pub fn main_action(model: Model) -> Option(button.Main(Msg)) {
  case model.loaded {
    True -> Some(button.Main(icon.Add, "Add goal", AddClicked))
    False -> None
  }
}

// VIEWS -------------------------------------------------------------------------------------------

const form_id = "goal-form"

pub fn view(model: Model, me: String) -> Element(Msg) {
  html.section([class("goals")], [
    undo.snackbar(model.undo, "Goal deleted", UndoClicked, DeleteExpired),
    html.div([class("toolbar")], [button.fab_for(main_action(model))]),
    form_view(model),
    case model.loaded, mine(model, me) {
      False, _ -> progress.loading("Loading…")
      True, [] ->
        empty.view(
          icon.Flag,
          "No goals yet",
          "Add a race you are training for: its distance and the time you want to run it in.",
          None,
        )
      True, goals -> layout.list(list.map(goals, row_view))
    },
  ])
}

fn row_view(g: Goal) -> Element(Msg) {
  html.li([], [
    // A goal opens in its form from anywhere on its row (ADR 0080).
    layout.row_button(goal.distance(g), EditClicked(g.id)),
    html.p([class("muted")], [html.text(goal.time_and_pace(g))]),
  ])
}

/// Adding and editing happen in a full-screen dialog (ADR 0057).
fn form_view(model: Model) -> Element(Msg) {
  let #(open, title) = case model.mode {
    Adding -> #(True, "New goal")
    Editing(_) -> #(True, "Edit goal")
    Browsing -> #(False, "")
  }
  form_dialog.view_with_action(
    "goal-form-dialog",
    open,
    title,
    form_id,
    "Save",
    CancelClicked,
    // A goal is deleted from its form, with Undo (ADR 0056, 0080).
    case model.mode {
      Editing(id) ->
        button.icon(
          [attribute.type_("button"), event.on_click(DeleteClicked(id))],
          icon.Delete,
          "Delete goal",
        )
      _ -> element.none()
    },
    [form_fields(model)],
  )
}

fn form_fields(model: Model) -> Element(Msg) {
  // A problem shows under the field it is about (ADR 0059).
  let on = fn(help, field_id) {
    field.with_error(help, field_id, model.error_field, model.error)
  }
  html.form(
    [
      attribute.id(form_id),
      class("goal-form"),
      event.on_submit(fn(_) { Submitted }),
    ],
    [
      // Side by side from 600px, like the form's other pairs (ADR 0085).
      html.div([class("row")], [
        field.text(
          "distance",
          "Distance",
          on(field.Help("For example 10 or 42.195", "km", None), "distance"),
          [
            attribute.type_("text"),
            attribute.attribute("inputmode", "decimal"),
            attribute.name("distance_km"),
            attribute.required(True),
            attribute.value(model.form.distance_km),
            event.on_input(DistanceChanged),
          ],
        ),
        field.text(
          "time",
          "Time",
          on(
            field.help("h:mm:ss, h:mm or minutes, for example 0:45:30"),
            "time",
          ),
          [
            attribute.type_("text"),
            attribute.name("time"),
            attribute.required(True),
            attribute.value(model.form.time),
            event.on_input(TimeChanged),
          ],
        ),
      ]),
    ],
  )
}
