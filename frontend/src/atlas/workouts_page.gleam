//// The workouts of one plan, laid out as weeks and days, with forms to add, change and remove them.
//// Own state and messages, embedded by the app; writes come back as `Action`s (ADR 0020, 0022).

import atlas/collection
import atlas/outbox
import atlas/plan.{type Kind, type Workout}
import atlas/plan_schedule
import atlas/random
import atlas/records
import atlas/store
import atlas/ui/button
import atlas/ui/dialog
import atlas/ui/error
import atlas/ui/field
import atlas/units
import atlas/workout_form.{type Row}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Mode {
  Browsing
  Adding
  Editing(id: String)
}

pub type Model {
  Model(
    /// The workouts of every plan on the device; the views pick the plan they show.
    rows: List(Row),
    loaded: Bool,
    mode: Mode,
    form: workout_form.Form,
    /// The workout whose "Delete" was clicked once.
    confirming: Option(String),
  )
}

pub type Msg {
  Refresh
  WorkoutsRead(Result(List(Dynamic), Nil))
  AddClicked(week: Int, day: Int)
  EditClicked(String)
  CancelClicked
  WeekChanged(String)
  DayChanged(String)
  TitleChanged(String)
  KindChanged(String)
  DistanceChanged(String)
  DurationChanged(String)
  DescriptionChanged(String)
  Submitted
  DeleteClicked(String)
  DeleteConfirmed(String)
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model([], False, Browsing, workout_form.empty_for(1, 1), None)
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Workouts, fn(result) {
      dispatch(WorkoutsRead(result))
    })
  })
}

/// The workouts of a plan that are on the device.
pub fn rows_of(model: Model, plan_id: String) -> List(Row) {
  list.filter(model.rows, fn(row) { row.workout.plan_id == plan_id })
}

fn workouts_of(model: Model, plan_id: String) -> List(Workout) {
  list.map(rows_of(model, plan_id), fn(row) { row.workout })
}

/// `plan_id` is the plan on screen. Changes are only made to it, and only when `can_edit`.
pub fn update(
  model: Model,
  msg: Msg,
  plan_id: String,
  can_edit: Bool,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    WorkoutsRead(Ok(stored)) -> {
      let rows = records.live(stored, records.workout_row)
      let mode = case model.mode {
        Editing(id) ->
          case list.any(rows, fn(row) { row.workout.id == id }) {
            True -> model.mode
            False -> Browsing
          }
        other -> other
      }
      #(Model(..model, rows: rows, loaded: True, mode: mode), effect.none(), [])
    }
    WorkoutsRead(Error(Nil)) -> #(model, effect.none(), [])

    AddClicked(week, day) ->
      case can_edit {
        True -> #(
          Model(
            ..model,
            mode: Adding,
            form: workout_form.empty_for(week, day),
            confirming: None,
          ),
          effect.none(),
          [],
        )
        False -> #(model, effect.none(), [])
      }

    EditClicked(id) ->
      case can_edit, find(rows_of(model, plan_id), id) {
        True, Ok(row) -> #(
          Model(
            ..model,
            mode: Editing(id),
            form: workout_form.from_row(row),
            confirming: None,
          ),
          effect.none(),
          [],
        )
        _, _ -> #(model, effect.none(), [])
      }

    CancelClicked -> #(
      Model(..model, mode: Browsing, confirming: None),
      effect.none(),
      [],
    )

    WeekChanged(value) ->
      typed(model, fn(f) { workout_form.Form(..f, week: value) })
    DayChanged(value) ->
      typed(model, fn(f) { workout_form.Form(..f, day: value) })
    TitleChanged(value) ->
      typed(model, fn(f) { workout_form.Form(..f, title: value) })
    KindChanged(value) ->
      typed(model, fn(f) {
        workout_form.Form(..f, kind: kind_from_value(value, f.kind))
      })
    DistanceChanged(value) ->
      typed(model, fn(f) { workout_form.Form(..f, distance_km: value) })
    DurationChanged(value) ->
      typed(model, fn(f) { workout_form.Form(..f, duration: value) })
    DescriptionChanged(value) ->
      typed(model, fn(f) { workout_form.Form(..f, description: value) })

    Submitted ->
      case can_edit, workout_form.validate(model.form) {
        False, _ -> #(model, effect.none(), [])
        True, Error(message) -> #(
          Model(
            ..model,
            form: workout_form.Form(..model.form, error: Some(message)),
          ),
          effect.none(),
          [],
        )
        True, Ok(valid) -> {
          let here = workouts_of(model, plan_id)
          let finished = Model(..model, mode: Browsing)
          case model.mode {
            Adding -> #(finished, effect.none(), [
              Create(
                random.new_id(),
                workout_form.create_fields(
                  plan_id,
                  plan_schedule.next_position(here, valid.day_index),
                  valid,
                ),
              ),
            ])
            Editing(id) ->
              case find(rows_of(model, plan_id), id) {
                Ok(row) -> {
                  let fields =
                    workout_form.changed_fields(
                      row,
                      valid,
                      plan_schedule.next_position(here, valid.day_index),
                    )
                  #(finished, effect.none(), case dict.is_empty(fields) {
                    True -> []
                    False -> [Edit(id, fields, row.updated)]
                  })
                }
                Error(Nil) -> #(finished, effect.none(), [])
              }
            Browsing -> #(model, effect.none(), [])
          }
        }
      }

    DeleteClicked(id) -> #(
      Model(..model, confirming: Some(id)),
      dialog.show(confirm_dialog_id(id)),
      [],
    )

    DeleteConfirmed(id) ->
      case can_edit, find(rows_of(model, plan_id), id) {
        True, Ok(row) -> #(
          Model(..model, mode: Browsing, confirming: None),
          effect.none(),
          [Delete(id, row.updated)],
        )
        _, _ -> #(model, effect.none(), [])
      }
  }
}

fn typed(
  model: Model,
  change: fn(workout_form.Form) -> workout_form.Form,
) -> #(Model, Effect(Msg), List(Action)) {
  let changed = change(model.form)
  #(
    Model(..model, form: workout_form.Form(..changed, error: None)),
    effect.none(),
    [],
  )
}

fn find(rows: List(Row), id: String) -> Result(Row, Nil) {
  list.find(rows, fn(row) { row.workout.id == id })
}

const kinds = [
  plan.Easy,
  plan.Long,
  plan.Tempo,
  plan.Interval,
  plan.Race,
  plan.Rest,
  plan.Cross,
  plan.Strength,
]

fn kind_from_value(value: String, fallback: Kind) -> Kind {
  case plan.kind_from_string(value) {
    Ok(kind) -> kind
    Error(Nil) -> fallback
  }
}

// VIEWS -------------------------------------------------------------------------------------------

pub fn view(model: Model, plan_id: String, can_edit: Bool) -> Element(Msg) {
  let rows = rows_of(model, plan_id)
  let weeks = plan_schedule.weeks(list.map(rows, fn(row) { row.workout }))
  html.section([class("workouts")], [
    html.div([class("toolbar")], [
      html.h2([], [html.text("Workouts")]),
      case can_edit, model.mode {
        True, Browsing ->
          button.primary(
            [attribute.type_("button"), event.on_click(AddClicked(next_week(weeks), 1))],
            [html.text("Add workout")],
          )
        _, _ -> element.none()
      },
    ]),
    case model.mode, can_edit {
      Adding, True -> form_view(model.form, "Add workout")
      _, _ -> element.none()
    },
    case model.loaded, weeks, model.mode {
      False, _, _ -> html.p([class("muted")], [html.text("Loading…")])
      True, [], Adding -> element.none()
      True, [], _ ->
        html.p([class("muted")], [
          html.text(case can_edit {
            True -> "This plan has no workouts yet. Add the first one."
            False -> "This plan has no workouts yet."
          }),
        ])
      True, _, _ ->
        html.div(
          [],
          list.map(weeks, fn(week) { week_view(week, rows, model, can_edit) }),
        )
    },
  ])
}

/// A new workout goes to the first day after the last week that has one, unless the user picks another.
fn next_week(weeks: List(plan_schedule.Week)) -> Int {
  case list.last(weeks) {
    Ok(last) -> last.number
    Error(Nil) -> 1
  }
}

fn week_view(
  week: plan_schedule.Week,
  rows: List(Row),
  model: Model,
  can_edit: Bool,
) -> Element(Msg) {
  html.div([class("week")], [
    html.h3([], [
      html.text("Week " <> int.to_string(week.number)),
      html.span([class("totals")], [html.text(totals(week))]),
    ]),
    html.ul(
      [class("days")],
      list.map(week.days, fn(day) { day_view(week, day, rows, model, can_edit) }),
    ),
  ])
}

fn totals(week: plan_schedule.Week) -> String {
  case week.distance_m >. 0.0, week.duration_s > 0 {
    False, False -> ""
    True, False -> " · " <> units.format_distance_km(week.distance_m)
    False, True -> " · " <> units.format_duration(week.duration_s)
    True, True ->
      " · "
      <> units.format_distance_km(week.distance_m)
      <> " · "
      <> units.format_duration(week.duration_s)
  }
}

fn day_view(
  week: plan_schedule.Week,
  day: plan_schedule.Day,
  rows: List(Row),
  model: Model,
  can_edit: Bool,
) -> Element(Msg) {
  html.li([class("day")], [
    html.span([class("day-name")], [
      html.text("Day " <> int.to_string(day.number)),
    ]),
    html.div(
      [class("day-body")],
      list.append(
        list.map(day.workouts, fn(w) {
          case list.find(rows, fn(row) { row.workout.id == w.id }) {
            Ok(row) ->
              case model.mode {
                Editing(editing) if editing == w.id ->
                  form_view(model.form, "Save changes")
                _ -> workout_view(row, can_edit)
              }
            Error(Nil) -> element.none()
          }
        }),
        [
          case can_edit, model.mode {
            True, Browsing ->
              button.link(
                [
                  attribute.type_("button"),
                  attribute.attribute(
                    "aria-label",
                    "Add a workout to week "
                      <> int.to_string(week.number)
                      <> ", day "
                      <> int.to_string(day.number),
                  ),
                  event.on_click(AddClicked(week.number, day.number)),
                ],
                [html.text("+ Add")],
              )
            _, _ -> element.none()
          },
        ],
      ),
    ),
  ])
}

fn workout_view(row: Row, can_edit: Bool) -> Element(Msg) {
  let w = row.workout
  html.div([class("workout")], [
    html.div([], [
      html.strong([], [html.text(w.title)]),
      html.span([class("badge")], [html.text(workout_form.kind_label(w.kind))]),
    ]),
    case targets(w) {
      "" -> element.none()
      text -> html.p([class("muted")], [html.text(text)])
    },
    case row.description {
      "" -> element.none()
      text -> html.p([class("description")], [html.text(text)])
    },
    case can_edit {
      False -> element.none()
      True ->
        html.div([class("actions")], [
          button.secondary(
            [attribute.type_("button"), event.on_click(EditClicked(w.id))],
            [html.text("Edit")],
          ),
          button.secondary(
            [attribute.type_("button"), event.on_click(DeleteClicked(w.id))],
            [html.text("Delete")],
          ),
          dialog.view(
            confirm_dialog_id(w.id),
            "Delete this workout?",
            CancelClicked,
            [
              button.danger(
                [attribute.type_("submit"), event.on_click(DeleteConfirmed(w.id))],
                [html.text("Yes, delete it")],
              ),
              button.secondary(
                [attribute.type_("submit"), event.on_click(CancelClicked)],
                [html.text("Keep it")],
              ),
            ],
          ),
        ])
    },
  ])
}

fn confirm_dialog_id(id: String) -> String {
  "confirm-delete-workout-" <> id
}

fn targets(w: Workout) -> String {
  case w.distance_m, w.duration_s {
    Some(d), Some(t) ->
      units.format_distance_km(d) <> " · " <> units.format_duration(t)
    Some(d), None -> units.format_distance_km(d)
    None, Some(t) -> units.format_duration(t)
    None, None -> ""
  }
}

fn form_view(form: workout_form.Form, submit_label: String) -> Element(Msg) {
  html.form([class("workout-form"), event.on_submit(fn(_) { Submitted })], [
    html.div([class("row")], [
      html.div([], [
        html.label([attribute.for("workout-week")], [html.text("Week")]),
        field.input([
          attribute.id("workout-week"),
          attribute.type_("number"),
          attribute.name("week"),
          attribute.attribute("min", "1"),
          attribute.attribute("max", int.to_string(workout_form.max_weeks)),
          attribute.value(form.week),
          event.on_input(WeekChanged),
        ]),
      ]),
      html.div([], [
        html.label([attribute.for("workout-day")], [html.text("Day")]),
        field.select(
          [
            attribute.id("workout-day"),
            attribute.name("day"),
            attribute.value(form.day),
            event.on_change(DayChanged),
          ],
          list.map([1, 2, 3, 4, 5, 6, 7], fn(n) {
            html.option(
              [attribute.value(int.to_string(n))],
              "Day " <> int.to_string(n),
            )
          }),
        ),
      ]),
    ]),
    html.label([attribute.for("workout-title")], [html.text("Title")]),
    field.input([
      attribute.id("workout-title"),
      attribute.type_("text"),
      attribute.name("title"),
      attribute.value(form.title),
      attribute.attribute("maxlength", "200"),
      attribute.required(True),
      event.on_input(TitleChanged),
    ]),
    html.label([attribute.for("workout-kind")], [html.text("Kind")]),
    field.select(
      [
        attribute.id("workout-kind"),
        attribute.name("kind"),
        attribute.value(plan.kind_to_string(form.kind)),
        event.on_change(KindChanged),
      ],
      list.map(kinds, fn(kind) {
        html.option(
          [attribute.value(plan.kind_to_string(kind))],
          workout_form.kind_label(kind),
        )
      }),
    ),
    html.div([class("row")], [
      html.div([], [
        html.label([attribute.for("workout-distance")], [
          html.text("Distance (km)"),
        ]),
        field.input([
          attribute.id("workout-distance"),
          attribute.type_("text"),
          attribute.attribute("inputmode", "decimal"),
          attribute.name("distance"),
          attribute.value(form.distance_km),
          attribute.placeholder("8.5"),
          event.on_input(DistanceChanged),
        ]),
      ]),
      html.div([], [
        html.label([attribute.for("workout-duration")], [
          html.text("Time (minutes or h:mm)"),
        ]),
        field.input([
          attribute.id("workout-duration"),
          attribute.type_("text"),
          attribute.name("duration"),
          attribute.value(form.duration),
          attribute.placeholder("45 or 1:30"),
          event.on_input(DurationChanged),
        ]),
      ]),
    ]),
    html.label([attribute.for("workout-description")], [html.text("Notes")]),
    field.textarea(
      [
        attribute.id("workout-description"),
        attribute.name("description"),
        attribute.rows(3),
        event.on_input(DescriptionChanged),
      ],
      form.description,
    ),
    case form.error {
      Some(message) -> error.message(message)
      None -> element.none()
    },
    html.div([class("actions")], [
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
