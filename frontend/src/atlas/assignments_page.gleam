//// The schedule of one plan: who is following it, from which day, and the means to start it for
//// oneself or (as a coach) for an athlete. Own state and messages; writes come back as `Action`s
//// (ADR 0020, 0023).

import atlas/assignment_form.{type Row}
import atlas/collection
import atlas/date.{type Date}
import atlas/grants.{type Grant, type Person}
import atlas/outbox
import atlas/plan.{type Workout}
import atlas/random
import atlas/records
import atlas/store
import atlas/ui/button
import atlas/ui/date_picker
import atlas/ui/error
import atlas/ui/field
import atlas/ui/form_dialog
import atlas/ui/icon
import atlas/ui/layout
import atlas/ui/menu
import atlas/ui/progress
import atlas/ui/undo.{type Undo}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Mode {
  Browsing
  Starting
  ChangingDate(id: String)
}

pub type Model {
  Model(
    /// The assignments of every plan on the device; the view picks the plan on screen.
    rows: List(Row),
    loaded: Bool,
    mode: Mode,
    form: assignment_form.Form,
    /// The assignment whose "Remove" was clicked once.
    /// A removal that can still be undone (ADR 0056).
    undo: Undo,
    /// The form's date picker (ADR 0054).
    date_picker: date_picker.State,
  )
}

/// What the screen needs to know that is not its own state.
pub type Context {
  Context(
    plan_id: String,
    user_id: String,
    /// Athletes the user may start this plan for (those who granted access), when the user may
    /// assign it at all: the plan must be their own or public (the server checks this, ADR 0009).
    athletes: List(Person),
    today: Date,
    /// Whether the user may start this plan at all: it must be their own or public (the server's rule, 0009).
    can_start: Bool,
  )
}

pub type Msg {
  Refresh
  AssignmentsRead(Result(List(Dynamic), Nil))
  StartClicked
  ChangeDateClicked(String)
  CancelClicked
  AthleteChanged(String)
  DateChanged(String)
  /// The picker's button was pressed; it opens on what the field holds now (ADR 0054).
  DatePickerOpened
  DatePicker(date_picker.Msg)
  Submitted
  /// Removes at once, with Undo for a few seconds (ADR 0056).
  RemoveClicked(String)
  UndoClicked
  RemoveExpired(Int)
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model(
    [],
    False,
    Browsing,
    assignment_form.empty_for("", date.Date(2026, 1, 1)),
    undo.new(),
    date_picker.new(),
  )
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Assignments, fn(result) {
      dispatch(AssignmentsRead(result))
    })
  })
}

/// The assignments of the plan that are on the device, soonest start first.
pub fn rows_of(model: Model, plan_id: String) -> List(Row) {
  model.rows
  |> list.filter(fn(row) { row.assignment.plan_id == plan_id })
  |> list.sort(fn(a, b) {
    date.compare(a.assignment.start_date, b.assignment.start_date)
  })
}

/// Whether the user may change or remove an assignment (the server's rule, 0009).
pub fn may_change(row: Row, user_id: String) -> Bool {
  row.assignment.athlete_id == user_id || row.assigned_by == user_id
}

pub fn update(
  model: Model,
  msg: Msg,
  context: Context,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    AssignmentsRead(Ok(stored)) -> {
      let rows = records.live(stored, records.assignment_row)
      let mode = case model.mode {
        ChangingDate(id) ->
          case list.any(rows, fn(row) { row.assignment.id == id }) {
            True -> model.mode
            False -> Browsing
          }
        other -> other
      }
      #(Model(..model, rows: rows, loaded: True, mode: mode), effect.none(), [])
    }
    AssignmentsRead(Error(Nil)) -> #(model, effect.none(), [])

    StartClicked ->
      case context.can_start {
        False -> #(model, effect.none(), [])
        True -> #(
          Model(
            ..model,
            mode: Starting,
            form: assignment_form.empty_for(context.user_id, context.today),
          ),
          effect.none(),
          [],
        )
      }

    ChangeDateClicked(id) ->
      case find(rows_of(model, context.plan_id), id) {
        Ok(row) ->
          case may_change(row, context.user_id) {
            True -> #(
              Model(
                ..model,
                mode: ChangingDate(id),
                form: assignment_form.from_row(row),
              ),
              effect.none(),
              [],
            )
            False -> #(model, effect.none(), [])
          }
        Error(Nil) -> #(model, effect.none(), [])
      }

    CancelClicked -> #(Model(..model, mode: Browsing), effect.none(), [])

    AthleteChanged(id) ->
      typed(model, fn(f) { assignment_form.Form(..f, athlete_id: id) })
    DateChanged(text) ->
      typed(model, fn(f) { assignment_form.Form(..f, start_date: text) })
    DatePickerOpened ->
      update(
        model,
        DatePicker(date_picker.Opened(model.form.start_date, context.today)),
        context,
      )
    DatePicker(inner) -> {
      let #(state, picker_effect, picked) =
        date_picker.update(date_picker_id, model.date_picker, inner)
      let model = Model(..model, date_picker: state)
      let #(model, _, _) = case picked {
        Some(text) ->
          typed(model, fn(f) { assignment_form.Form(..f, start_date: text) })
        None -> #(model, effect.none(), [])
      }
      #(model, effect.map(picker_effect, DatePicker), [])
    }

    Submitted ->
      case assignment_form.validate(model.form) {
        Error(message) -> #(
          Model(
            ..model,
            form: assignment_form.Form(..model.form, error: Some(message)),
          ),
          effect.none(),
          [],
        )
        Ok(valid) -> {
          let finished = Model(..model, mode: Browsing)
          case model.mode {
            Starting ->
              case allowed_athlete(valid.athlete_id, context) {
                False -> #(
                  Model(
                    ..model,
                    form: assignment_form.Form(
                      ..model.form,
                      error: Some("You cannot start this plan for that person."),
                    ),
                  ),
                  effect.none(),
                  [],
                )
                True -> #(finished, effect.none(), [
                  Create(
                    random.new_id(),
                    assignment_form.create_fields(
                      context.plan_id,
                      context.user_id,
                      valid,
                    ),
                  ),
                ])
              }
            ChangingDate(id) ->
              case find(rows_of(model, context.plan_id), id) {
                Ok(row) -> {
                  let fields = assignment_form.changed_fields(row, valid)
                  #(
                    finished,
                    effect.none(),
                    case
                      dict.is_empty(fields) || !may_change(row, context.user_id)
                    {
                      True -> []
                      False -> [Edit(id, fields, row.updated)]
                    },
                  )
                }
                Error(Nil) -> #(finished, effect.none(), [])
              }
            Browsing -> #(model, effect.none(), [])
          }
        }
      }

    RemoveClicked(id) ->
      case removal_of(model, context, id) {
        [] -> #(model, effect.none(), [])
        _ -> {
          let #(next, earlier, wait) = undo.start(model.undo, id, RemoveExpired)
          #(
            Model(..model, undo: next, mode: Browsing),
            wait,
            option.map(earlier, removal_of(model, context, _))
              |> option.unwrap([]),
          )
        }
      }

    UndoClicked -> #(
      Model(..model, undo: undo.cancel(model.undo)),
      effect.none(),
      [],
    )

    RemoveExpired(n) -> {
      let #(next, due) = undo.expire(model.undo, n)
      #(
        Model(..model, undo: next),
        effect.none(),
        option.map(due, removal_of(model, context, _)) |> option.unwrap([]),
      )
    }
  }
}

fn allowed_athlete(athlete_id: String, context: Context) -> Bool {
  athlete_id == context.user_id
  || list.any(context.athletes, fn(person) { person.id == athlete_id })
}

fn typed(
  model: Model,
  change: fn(assignment_form.Form) -> assignment_form.Form,
) -> #(Model, Effect(Msg), List(Action)) {
  let changed = change(model.form)
  #(
    Model(..model, form: assignment_form.Form(..changed, error: None)),
    effect.none(),
    [],
  )
}

fn find(rows: List(Row), id: String) -> Result(Row, Nil) {
  list.find(rows, fn(row) { row.assignment.id == id })
}

// VIEWS -------------------------------------------------------------------------------------------

/// `workouts` are those of the plan on screen (for the end date); `all_grants` give people their names.
pub fn view(
  model: Model,
  context: Context,
  workouts: List(Workout),
  all_grants: List(Grant),
) -> Element(Msg) {
  // An entry being removed is left out while its Undo lasts (ADR 0056).
  let rows =
    rows_of(model, context.plan_id)
    |> list.filter(fn(row) { !undo.hides(model.undo, row.assignment.id) })
  html.section([class("schedule")], [
    undo.snackbar(
      model.undo,
      "Removed from the schedule",
      UndoClicked,
      RemoveExpired,
    ),
    // The plan's tabs name this section (ADR 0058); starting the plan is its floating action button.
    case model.mode {
      Browsing if context.can_start ->
        button.fab(
          [attribute.type_("button"), event.on_click(StartClicked)],
          icon.PlayArrow,
          case context.athletes {
            [] -> "Start this plan"
            _ -> "Start or assign"
          },
        )
      _ -> element.none()
    },
    form_view(model, context),
    case model.loaded, rows {
      False, _ -> progress.loading("Loading…")
      True, [] ->
        case model.mode {
          Starting -> element.none()
          _ ->
            html.p([class("muted")], [
              html.text(case context.can_start {
                True ->
                  "Nobody is following this plan yet. Pick a start date to begin."
                False -> "Nobody is following this plan yet."
              }),
            ])
        }
      True, _ ->
        layout.list(
          list.map(rows, fn(row) {
            row_view(row, context, workouts, all_grants)
          }),
        )
    },
  ])
}

fn row_view(
  row: Row,
  context: Context,
  workouts: List(Workout),
  all_grants: List(Grant),
) -> Element(Msg) {
  let a = row.assignment
  html.li([], [
    html.div([], [
      html.strong([], [
        html.text(who(a.athlete_id, context.user_id, all_grants)),
      ]),
      html.p([class("muted")], [
        html.text(
          "Starts "
          <> date.format(a.start_date)
          <> case plan.end_date(a, workouts) {
            Ok(end) -> " · ends " <> date.format(end)
            Error(Nil) -> ""
          },
        ),
      ]),
      case row.assigned_by != a.athlete_id && row.assigned_by != "" {
        True ->
          html.p([class("muted")], [
            html.text(
              "Assigned by "
              <> who(row.assigned_by, context.user_id, all_grants),
            ),
          ])
        False -> element.none()
      },
      case may_change(row, context.user_id) {
        False -> element.none()
        True -> actions(row)
      },
    ]),
  ])
}

/// The delete to write for an assignment, looked up among all of them (another plan may be open by the time its
/// Undo runs out), if the user may change it.
fn removal_of(model: Model, context: Context, id: String) -> List(Action) {
  case list.find(model.rows, fn(row) { row.assignment.id == id }) {
    Ok(row) ->
      case may_change(row, context.user_id) {
        True -> [Delete(id, row.updated)]
        False -> []
      }
    Error(Nil) -> []
  }
}

/// An assignment's actions are in a menu at the end of its row (ADR 0056).
fn actions(row: Row) -> Element(Msg) {
  let id = row.assignment.id
  menu.view("assignment-menu-" <> id, "More for this schedule entry", [
    menu.Item(icon.CalendarToday, "Change date", ChangeDateClicked(id)),
    menu.Item(icon.Delete, "Remove", RemoveClicked(id)),
  ])
}

fn who(user_id: String, me: String, all_grants: List(Grant)) -> String {
  case user_id == me {
    True -> "You"
    False ->
      case grants.name_of(all_grants, user_id) {
        Some(name) -> name
        None -> "Someone"
      }
  }
}

/// `new_assignment`: starting a plan (the athlete can be chosen) rather than changing a date (it cannot).
const date_picker_id = "assign-start-picker"

const form_id = "schedule-form"

/// Starting a plan and changing a start date happen in a full-screen dialog (ADR 0057).
fn form_view(model: Model, context: Context) -> Element(Msg) {
  let #(open, title, new_assignment) = case model.mode {
    Starting -> #(True, "Start plan", True)
    ChangingDate(_) -> #(True, "Change start date", False)
    Browsing -> #(False, "", False)
  }
  form_dialog.view(
    "schedule-form-dialog",
    open,
    title,
    form_id,
    "Save",
    CancelClicked,
    // The picker's dialog holds a form of its own, so it sits beside this form, not in it.
    [
      form_fields(model.form, context, new_assignment),
      date_picker.view(
        date_picker_id,
        model.date_picker,
        context.today,
        DatePicker,
      ),
    ],
  )
}

fn form_fields(
  form: assignment_form.Form,
  context: Context,
  new_assignment: Bool,
) -> Element(Msg) {
  let choosing_athlete = new_assignment && context.athletes != []
  // A problem shows under the field it is about (ADR 0059).
  let wrong = assignment_form.error_field(form)
  let on = fn(help, field_name) {
    field.with_error(help, field_name, wrong, form.error)
  }
  html.form(
    [
      attribute.id(form_id),
      class("schedule-form"),
      event.on_submit(fn(_) { Submitted }),
    ],
    [
      case choosing_athlete {
        False -> element.none()
        True ->
          field.choose(
            "assign-athlete",
            "For",
            on(field.plain, "athlete"),
            [attribute.name("athlete"), event.on_change(AthleteChanged)],
            form.athlete_id,
            [
              #(context.user_id, "Myself"),
              ..list.map(context.athletes, fn(person) {
                #(person.id, person.name)
              })
            ],
          )
      },
      field.with_trigger(
        field.text(
          "assign-start",
          "First day of the plan",
          on(field.plain, "start"),
          [
            attribute.type_("date"),
            attribute.name("start_date"),
            attribute.value(form.start_date),
            attribute.required(True),
            event.on_input(DateChanged),
          ],
        ),
        date_picker.trigger(date_picker_id, DatePickerOpened),
      ),
      case form.error, wrong {
        Some(message), "" -> error.message(message)
        _, _ -> element.none()
      },
    ],
  )
}
