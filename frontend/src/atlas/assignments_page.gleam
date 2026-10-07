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
import atlas/ui/dialog
import atlas/ui/error
import atlas/ui/field
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
    confirming: Option(String),
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
  Submitted
  RemoveClicked(String)
  RemoveConfirmed(String)
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
    None,
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
            confirming: None,
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
                confirming: None,
              ),
              effect.none(),
              [],
            )
            False -> #(model, effect.none(), [])
          }
        Error(Nil) -> #(model, effect.none(), [])
      }

    CancelClicked -> #(
      Model(..model, mode: Browsing, confirming: None),
      effect.none(),
      [],
    )

    AthleteChanged(id) ->
      typed(model, fn(f) { assignment_form.Form(..f, athlete_id: id) })
    DateChanged(text) ->
      typed(model, fn(f) { assignment_form.Form(..f, start_date: text) })

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

    RemoveClicked(id) -> #(
      Model(..model, confirming: Some(id)),
      dialog.show(confirm_dialog_id(id)),
      [],
    )

    RemoveConfirmed(id) ->
      case find(rows_of(model, context.plan_id), id) {
        Ok(row) ->
          case may_change(row, context.user_id) {
            True -> #(
              Model(..model, mode: Browsing, confirming: None),
              effect.none(),
              [Delete(id, row.updated)],
            )
            False -> #(model, effect.none(), [])
          }
        Error(Nil) -> #(model, effect.none(), [])
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
  let rows = rows_of(model, context.plan_id)
  html.section([class("schedule")], [
    html.div([class("toolbar")], [
      html.h2([], [html.text("Schedule")]),
      case model.mode {
        Browsing if context.can_start ->
          button.primary(
            [attribute.type_("button"), event.on_click(StartClicked)],
            [
              html.text(case context.athletes {
                [] -> "Start this plan"
                _ -> "Start or assign"
              }),
            ],
          )
        _ -> element.none()
      },
    ]),
    case model.mode {
      Starting -> form_view(model.form, context, "Start plan", True)
      _ -> element.none()
    },
    case model.loaded, rows {
      False, _ -> html.p([class("muted")], [html.text("Loading…")])
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
        layout.cards(
          list.map(rows, fn(row) {
            row_view(row, model, context, workouts, all_grants)
          }),
        )
    },
  ])
}

fn row_view(
  row: Row,
  model: Model,
  context: Context,
  workouts: List(Workout),
  all_grants: List(Grant),
) -> Element(Msg) {
  let a = row.assignment
  html.li([], [
    case model.mode {
      ChangingDate(editing) if editing == a.id ->
        form_view(model.form, context, "Save date", False)
      _ ->
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
        ])
    },
  ])
}

fn confirm_dialog_id(id: String) -> String {
  "confirm-remove-assignment-" <> id
}

fn actions(row: Row) -> Element(Msg) {
  let id = row.assignment.id
  layout.actions([
    button.secondary(
      [attribute.type_("button"), event.on_click(ChangeDateClicked(id))],
      [html.text("Change date")],
    ),
    button.secondary(
      [attribute.type_("button"), event.on_click(RemoveClicked(id))],
      [html.text("Remove")],
    ),
    dialog.view(
      confirm_dialog_id(id),
      "Remove this from the schedule?",
      CancelClicked,
      [
        button.danger(
          [attribute.type_("submit"), event.on_click(RemoveConfirmed(id))],
          [html.text("Yes, remove it")],
        ),
        button.secondary(
          [attribute.type_("submit"), event.on_click(CancelClicked)],
          [html.text("Keep it")],
        ),
      ],
    ),
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
fn form_view(
  form: assignment_form.Form,
  context: Context,
  submit_label: String,
  new_assignment: Bool,
) -> Element(Msg) {
  let choosing_athlete = new_assignment && context.athletes != []
  html.form([class("schedule-form"), event.on_submit(fn(_) { Submitted })], [
    case choosing_athlete {
      False -> element.none()
      True ->
        html.div([], [
          html.label([attribute.for("assign-athlete")], [html.text("For")]),
          field.select(
            [
              attribute.id("assign-athlete"),
              attribute.name("athlete"),
              event.on_change(AthleteChanged),
            ],
            form.athlete_id,
            [
              #(context.user_id, "Myself"),
              ..list.map(context.athletes, fn(person) {
                #(person.id, person.name)
              })
            ],
          ),
        ])
    },
    html.label([attribute.for("assign-start")], [
      html.text("First day of the plan"),
    ]),
    field.input([
      attribute.id("assign-start"),
      attribute.type_("date"),
      attribute.name("start_date"),
      attribute.value(form.start_date),
      attribute.required(True),
      event.on_input(DateChanged),
    ]),
    case form.error {
      Some(message) -> error.message(message)
      None -> element.none()
    },
    layout.actions([
      button.primary([attribute.type_("submit")], [
        html.text(submit_label),
      ]),
      button.secondary(
        [attribute.type_("button"), event.on_click(CancelClicked)],
        [html.text("Cancel")],
      ),
    ]),
  ])
}
