//// The workouts of one plan as a calendar: a row per week, a column per day, grouped by the plan's phases. A week's
//// row shows its distance against its goal; a week and a workout open in a dialog (ADR 0022, 0043, 0066).
//// Own state and messages, embedded by the app; writes come back as `Action`s (ADR 0020).

import atlas/collection
import atlas/outbox
import atlas/plan.{type Kind, type Plan, type Workout}
import atlas/plan_form
import atlas/plan_schedule
import atlas/random
import atlas/records
import atlas/store
import atlas/ui/button
import atlas/ui/chip
import atlas/ui/choice
import atlas/ui/dialog
import atlas/ui/empty
import atlas/ui/error
import atlas/ui/field
import atlas/ui/focus
import atlas/ui/form_dialog
import atlas/ui/icon
import atlas/ui/progress
import atlas/ui/undo.{type Undo}
import atlas/units
import atlas/workout_form.{type Row}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const form_title_id = "workout-title"

pub type Mode {
  Browsing
  /// A workout shown in its dialog.
  Viewing(id: String)
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
    /// A delete that can still be undone (ADR 0056).
    undo: Undo,
    /// The week last chosen, from 1: the one whose dialog opens, and where a new workout goes.
    selected_week: Int,
    /// Where the intensity slider of a week is while it is being dragged, before it is let go.
    intensity_draft: Option(#(Int, Float)),
    /// Whether the selected week's dialog is open (ADR 0066).
    week_open: Bool,
  )
}

pub type Msg {
  Refresh
  WorkoutsRead(Result(List(Dynamic), Nil))
  WeekSelected(Int)
  WorkoutSelected(String)
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
  /// Deletes at once, with Undo for a few seconds (ADR 0056).
  DeleteClicked(String)
  UndoClicked
  DeleteExpired(Int)
  /// The slider moved; nothing is written until it is let go.
  IntensityInput(String)
  /// The slider was let go (or moved with the keyboard): the value is written.
  IntensityChanged(String)
  IntensityCleared
  /// The week's dialog closed (ADR 0066).
  WeekClosed
  /// The workout's dialog closed.
  WorkoutClosed
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
  /// A change to the plan itself: its phases, goal or a week's intensity.
  EditPlan(id: String, fields: outbox.Fields, base_updated: String)
}

pub fn new() -> Model {
  Model(
    [],
    False,
    Browsing,
    workout_form.empty_for(1, 1),
    undo.new(),
    1,
    None,
    False,
  )
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

/// `on_screen` is the plan on screen. Changes are only made to it, and only when `can_edit`.
pub fn update(
  model: Model,
  msg: Msg,
  on_screen: Option(Plan),
  can_edit: Bool,
) -> #(Model, Effect(Msg), List(Action)) {
  let plan_id = case on_screen {
    Some(p) -> p.id
    None -> ""
  }
  let can_edit = can_edit && option.is_some(on_screen)
  case msg {
    Refresh -> #(model, refresh(), [])

    WorkoutsRead(Ok(stored)) -> {
      let rows = records.live(stored, records.workout_row)
      let mode = case model.mode {
        Editing(id) | Viewing(id) ->
          case list.any(rows, fn(row) { row.workout.id == id }) {
            True -> model.mode
            False -> Browsing
          }
        other -> other
      }
      #(Model(..model, rows: rows, loaded: True, mode: mode), effect.none(), [])
    }
    WorkoutsRead(Error(Nil)) -> #(model, effect.none(), [])

    // A week opens in its dialog (ADR 0066).
    WeekSelected(week) -> #(
      Model(
        ..model,
        selected_week: week,
        intensity_draft: None,
        week_open: True,
      ),
      effect.none(),
      [],
    )

    WeekClosed -> #(
      Model(..model, week_open: False, intensity_draft: None),
      effect.none(),
      [],
    )

    // Only closing the workout's own dialog ends the viewing; it also closes when Edit opens the form over it.
    WorkoutClosed ->
      case model.mode {
        Viewing(_) -> #(Model(..model, mode: Browsing), effect.none(), [])
        _ -> #(model, effect.none(), [])
      }

    // The owner opens a workout to change it, so it opens in its form; anyone else sees it in a dialog
    // (ADR 0080).
    WorkoutSelected(id) ->
      case can_edit, find(rows_of(model, plan_id), id) {
        True, Ok(_) -> update(model, EditClicked(id), on_screen, can_edit)
        False, Ok(row) -> #(
          Model(..model, mode: Viewing(id), selected_week: week_of(row.workout)),
          effect.none(),
          [],
        )
        _, Error(Nil) -> #(model, effect.none(), [])
      }

    AddClicked(week, day) ->
      case can_edit {
        True -> #(
          Model(
            ..model,
            mode: Adding,
            form: workout_form.empty_for(week, day),
            selected_week: week,
          ),
          focus.soon(form_title_id),
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
            selected_week: week_of(row.workout),
          ),
          focus.soon(form_title_id),
          [],
        )
        _, _ -> #(model, effect.none(), [])
      }

    CancelClicked -> #(Model(..model, mode: Browsing), effect.none(), [])

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
          let week = valid.day_index / 7 + 1
          case model.mode {
            Adding -> #(
              Model(..model, mode: Browsing, selected_week: week),
              effect.none(),
              [
                Create(
                  random.new_id(),
                  workout_form.create_fields(
                    plan_id,
                    plan_schedule.next_position(here, valid.day_index),
                    valid,
                  ),
                ),
              ],
            )
            Editing(id) -> {
              let finished = Model(..model, mode: Browsing, selected_week: week)
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
                Error(Nil) -> #(
                  Model(..finished, mode: Browsing),
                  effect.none(),
                  [],
                )
              }
            }
            Browsing | Viewing(_) -> #(model, effect.none(), [])
          }
        }
      }

    DeleteClicked(id) ->
      case can_edit, find(rows_of(model, plan_id), id) {
        True, Ok(_) -> {
          let #(next, earlier, wait) = undo.start(model.undo, id, DeleteExpired)
          #(
            Model(..model, undo: next, mode: Browsing),
            wait,
            option.map(earlier, delete_of(model, _)) |> option.unwrap([]),
          )
        }
        _, _ -> #(model, effect.none(), [])
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
        option.map(due, delete_of(model, _)) |> option.unwrap([]),
      )
    }

    IntensityInput(value) ->
      case can_edit, workout_form.parse_decimal(value) {
        True, Ok(level) -> #(
          Model(
            ..model,
            intensity_draft: Some(#(model.selected_week, plan.intensity(level))),
          ),
          effect.none(),
          [],
        )
        _, _ -> #(model, effect.none(), [])
      }

    IntensityChanged(value) ->
      case workout_form.parse_decimal(value) {
        Ok(level) -> set_intensity(model, on_screen, can_edit, Some(level))
        Error(Nil) -> #(model, effect.none(), [])
      }

    // Clear sits in the dialog's actions; the slider takes the focus once the week is cleared, as Clear goes away.
    IntensityCleared ->
      case set_intensity(model, on_screen, can_edit, None) {
        #(next, _, [_, ..] as actions) -> #(
          next,
          focus.soon("week-intensity"),
          actions,
        )
        unchanged -> unchanged
      }
  }
}

fn set_intensity(
  model: Model,
  on_screen: Option(Plan),
  can_edit: Bool,
  level: Option(Float),
) -> #(Model, Effect(Msg), List(Action)) {
  case can_edit, on_screen {
    True, Some(p) -> {
      let fields = plan_form.intensity_fields(p, model.selected_week, level)
      #(
        Model(..model, intensity_draft: None),
        effect.none(),
        case dict.is_empty(fields) {
          True -> []
          False -> [EditPlan(p.id, fields, p.updated)]
        },
      )
    }
    _, _ -> #(model, effect.none(), [])
  }
}

/// Closing a form over a workout goes back to showing it.
fn week_of(workout: Workout) -> Int {
  workout.day_index / 7 + 1
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

pub fn view(model: Model, on_screen: Plan, can_edit: Bool) -> Element(Msg) {
  // A workout being deleted is left out while its Undo lasts (ADR 0056).
  let rows =
    rows_of(model, on_screen.id)
    |> list.filter(fn(row) { !undo.hides(model.undo, row.workout.id) })
  let weeks =
    plan_schedule.weeks(
      on_screen.phases,
      list.map(rows, fn(row) { row.workout }),
    )
  html.section([class("workouts plan-calendar")], [
    undo.snackbar(model.undo, "Workout deleted", UndoClicked, DeleteExpired),
    form_view(model, on_screen, weeks, can_edit),
    // The plan's tabs name this section (ADR 0058); adding a workout is its main action (ADR 0068).
    button.fab_for(main_action(model, on_screen, can_edit)),
    html.div([class("calendar")], case model.loaded {
      False -> [progress.loading("Loading…")]
      True -> [
        case rows {
          [] ->
            empty.view(
              icon.CalendarToday,
              "No workouts yet",
              case can_edit {
                True -> "Add the first one with Add workout."
                False -> "The plan's owner has not added any workouts yet."
              },
              None,
            )
          _ -> element.none()
        },
        case weeks {
          [] -> element.none()
          _ ->
            html.div([], [
              calendar_head(),
              ..list.map(plan_schedule.bands(weeks), fn(band) {
                band_view(band, on_screen, rows, model, can_edit)
              })
            ])
        },
      ]
    }),
    workout_dialog(model, on_screen, rows),
    week_dialog(model, on_screen, weeks, can_edit),
  ])
}

fn clamp_week(week: Int, weeks: List(plan_schedule.Week)) -> Int {
  int.clamp(week, 1, int.max(list.length(weeks), 1))
}

fn calendar_head() -> Element(Msg) {
  html.div(
    [class("calendar-head"), attribute.attribute("aria-hidden", "true")],
    [
      html.span([], []),
      ..list.map([1, 2, 3, 4, 5, 6, 7], fn(n) {
        html.span([], [html.text("Day " <> int.to_string(n))])
      })
    ],
  )
}

fn band_view(
  band: plan_schedule.Band,
  on_screen: Plan,
  rows: List(Row),
  model: Model,
  can_edit: Bool,
) -> Element(Msg) {
  let #(name, modifier) = case band.phase {
    Ok(plan.Base) -> #("Base phase", "phase-base")
    Ok(plan.PreCompetition) -> #("Pre-competition phase", "phase-pre")
    Ok(plan.Competition) -> #("Competition phase", "phase-competition")
    Error(Nil) ->
      case plan.phase_weeks(on_screen.phases) {
        0 -> #("", "phase-none")
        _ -> #("After the competition phase", "phase-none")
      }
  }
  html.div([class("phase-band " <> modifier)], [
    case name {
      "" -> element.none()
      _ ->
        html.h3([class("band-title")], [
          html.text(name),
          html.span([class("totals")], [html.text(weeks_text(band.weeks))]),
        ])
    },
    ..list.map(band.weeks, fn(week) {
      week_row(week, on_screen, rows, model, can_edit)
    })
  ])
}

fn weeks_text(weeks: List(plan_schedule.Week)) -> String {
  case list.length(weeks) {
    1 -> " · 1 week"
    n -> " · " <> int.to_string(n) <> " weeks"
  }
}

fn week_row(
  week: plan_schedule.Week,
  on_screen: Plan,
  rows: List(Row),
  model: Model,
  can_edit: Bool,
) -> Element(Msg) {
  let selected = week.number == model.selected_week
  let intensity = dict.get(on_screen.week_intensity, week.number)
  let goal = plan_schedule.week_goal(on_screen.weekly_distance_m, intensity)
  html.div(
    [
      class("calendar-week"),
      attribute.classes([#("selected", selected)]),
    ],
    [
      html.button(
        [
          attribute.type_("button"),
          class("week-label"),
          attribute.attribute("aria-haspopup", "dialog"),
          event.on_click(WeekSelected(week.number)),
        ],
        [
          html.strong([], [html.text("Week " <> int.to_string(week.number))]),
          case intensity {
            Ok(level) -> intensity_chip(level)
            Error(Nil) -> element.none()
          },
          // The week's distance against its goal, always in view (ADR 0066).
          week_distance(week, goal),
        ],
      ),
      ..list.map(week.days, fn(day) {
        day_cell(week, day, rows, model, can_edit)
      })
    ],
  )
}

fn week_distance(
  week: plan_schedule.Week,
  goal: Option(Float),
) -> Element(Msg) {
  case goal, plan_schedule.goal_share(week, goal) {
    Some(g), Ok(share) ->
      html.span([class("week-distance")], [
        html.text(
          units.planned_km(week.distance_m)
          <> " / "
          <> units.format_planned_km(g),
        ),
        // Decorative: the text says the same.
        html.span(
          [
            class("goal-meter week-meter"),
            attribute.classes([#("over", share >. 1.0)]),
            attribute.attribute("aria-hidden", "true"),
          ],
          [
            html.span(
              [
                attribute.style(
                  "width",
                  int.to_string(int.min(float.round(share *. 100.0), 100))
                    <> "%",
                ),
              ],
              [],
            ),
          ],
        ),
      ])
    _, _ ->
      case week.distance_m >. 0.0 {
        True ->
          html.span([class("week-distance")], [
            html.text(units.format_planned_km(week.distance_m)),
          ])
        False -> element.none()
      }
  }
}

/// The percentage, colored by band: easy below 40%, moderate below 70%, hard from there.
fn intensity_chip(level: Float) -> Element(Msg) {
  let band = case level {
    _ if level <. 0.4 -> "low"
    _ if level <. 0.7 -> "medium"
    _ -> "high"
  }
  // "50%" next to a distance could be read as progress, so it says what it is to screen readers and on hover.
  html.span(
    [
      class("intensity intensity-" <> band),
      attribute.title("Intensity " <> plan.intensity_percent(level)),
    ],
    [
      html.span([class("visually-hidden")], [html.text("Intensity ")]),
      html.text(plan.intensity_percent(level)),
    ],
  )
}

fn day_cell(
  week: plan_schedule.Week,
  day: plan_schedule.Day,
  rows: List(Row),
  model: Model,
  can_edit: Bool,
) -> Element(Msg) {
  html.div([class("calendar-day")], [
    html.span([class("day-name")], [
      html.text("Day " <> int.to_string(day.number)),
    ]),
    html.div(
      [class("day-body")],
      list.append(
        list.filter_map(day.workouts, fn(w) {
          case list.find(rows, fn(row) { row.workout.id == w.id }) {
            Ok(_) -> Ok(workout_chip(w, week, day, model.mode))
            Error(Nil) -> Error(Nil)
          }
        }),
        [
          case can_edit {
            True ->
              html.button(
                [
                  attribute.type_("button"),
                  class("add-here"),
                  attribute.attribute(
                    "aria-label",
                    "Add a workout to week "
                      <> int.to_string(week.number)
                      <> ", day "
                      <> int.to_string(day.number),
                  ),
                  event.on_click(AddClicked(week.number, day.number)),
                ],
                [icon.view(icon.Add)],
              )
            False -> element.none()
          },
        ],
      ),
    ),
  ])
}

/// A workout in the calendar. Its kind is written out as well as shown by the colour of its bar, which some kinds
/// share; its name says the week and day, since the calendar's column heads are not read out (ADR 0070).
fn workout_chip(
  w: Workout,
  week: plan_schedule.Week,
  day: plan_schedule.Day,
  mode: Mode,
) -> Element(Msg) {
  let open = case mode {
    Viewing(id) | Editing(id) -> id == w.id
    _ -> False
  }
  let kind = workout_form.kind_label(w.kind)
  html.button(
    [
      attribute.type_("button"),
      class("workout kind-" <> plan.kind_to_string(w.kind)),
      attribute.classes([#("open", open)]),
      attribute.attribute("aria-haspopup", "dialog"),
      attribute.aria_label(
        [
          w.title,
          kind,
          "week "
            <> int.to_string(week.number)
            <> ", day "
            <> int.to_string(day.number),
          targets(w),
        ]
        |> list.filter(fn(part) { part != "" })
        |> string.join(", "),
      ),
      event.on_click(WorkoutSelected(w.id)),
    ],
    [
      html.span([class("workout-kind")], [html.text(kind)]),
      html.span([class("workout-title")], [html.text(w.title)]),
      case targets(w) {
        "" -> element.none()
        text -> html.span([class("workout-targets")], [html.text(text)])
      },
    ],
  )
}

// DIALOGS -----------------------------------------------------------------------------------------

/// The open workout, for those who cannot edit the plan (ADR 0066, 0080).
fn workout_dialog(
  model: Model,
  on_screen: Plan,
  rows: List(Row),
) -> Element(Msg) {
  let shown = case model.mode {
    Viewing(id) -> option.from_result(find(rows, id))
    _ -> None
  }
  case shown {
    None -> dialog.details("workout-dialog", False, "", WorkoutClosed, [], [])
    Some(row) -> {
      let w = row.workout
      dialog.details(
        "workout-dialog",
        True,
        w.title,
        WorkoutClosed,
        [
          html.p([class("muted")], [
            html.text(
              plan_schedule.week_label(on_screen.phases, week_of(w))
              <> " · day "
              <> int.to_string(w.day_index % 7 + 1),
            ),
          ]),
          html.p([], [chip.label(workout_form.kind_label(w.kind))]),
          case targets(w) {
            "" -> element.none()
            text -> html.p([], [html.text(text)])
          },
          case row.description {
            "" -> element.none()
            text -> html.p([class("description")], [html.text(text)])
          },
        ],
        // Only those who cannot edit the plan see a workout here; the owner gets its form (ADR 0080).
        [],
      )
    }
  }
}

/// The selected week: its intensity (set here by the owner) and its figures against its goal (ADR 0066).
fn week_dialog(
  model: Model,
  on_screen: Plan,
  weeks: List(plan_schedule.Week),
  can_edit: Bool,
) -> Element(Msg) {
  case
    model.week_open,
    list.find(weeks, fn(w) { w.number == model.selected_week })
  {
    True, Ok(week) -> {
      let intensity = dict.get(on_screen.week_intensity, week.number)
      // The week's goal follows its intensity (ADR 0064), also while the slider is being dragged.
      let goal =
        plan_schedule.week_goal(
          on_screen.weekly_distance_m,
          case model.intensity_draft {
            Some(#(dragged, level)) if dragged == week.number -> Ok(level)
            _ -> intensity
          },
        )
      dialog.details(
        "week-dialog",
        True,
        plan_schedule.week_label(on_screen.phases, week.number),
        WeekClosed,
        [
          intensity_view(model, week.number, intensity, can_edit),
          html.dl([class("facts")], [
            html.dt([], [html.text("Distance")]),
            html.dd([], [html.text(distance_text(week, goal))]),
            html.dt([], [html.text("Duration")]),
            html.dd([], [
              html.text(case week.duration_s {
                0 -> "—"
                s -> units.format_duration(s)
              }),
            ]),
            html.dt([], [html.text("Workouts")]),
            html.dd([], [html.text(int.to_string(workout_count(week)))]),
          ]),
          goal_meter(week, goal),
        ],
        // Clearing goes with Close rather than beside the slider, so the slider keeps its width when a week gets one.
        case can_edit, intensity {
          True, Ok(_) -> [
            button.text(
              [attribute.type_("button"), event.on_click(IntensityCleared)],
              [html.text("Clear intensity")],
            ),
          ]
          _, _ -> []
        },
      )
    }
    _, _ -> dialog.details("week-dialog", False, "", WeekClosed, [], [])
  }
}

fn intensity_view(
  model: Model,
  week: Int,
  stored: Result(Float, Nil),
  can_edit: Bool,
) -> Element(Msg) {
  let shown = case model.intensity_draft {
    Some(#(draft_week, value)) if draft_week == week -> Ok(value)
    _ -> stored
  }
  let text = case shown {
    Ok(value) -> plan.intensity_percent(value)
    Error(Nil) -> "Not set"
  }
  html.div([class("intensity-setting")], [
    // Only the slider can be labelled: someone who cannot edit sees the words and a bar.
    html.div([class("intensity-heading")], case can_edit {
      True -> [
        html.label([attribute.for("week-intensity")], [html.text("Intensity")]),
        html.output(
          [attribute.for("week-intensity"), class("intensity-value")],
          [html.text(text)],
        ),
      ]
      False -> [
        html.span([], [html.text("Intensity")]),
        html.span([class("intensity-value")], [html.text(text)]),
      ]
    }),
    case can_edit {
      False ->
        case shown {
          Ok(value) -> intensity_bar(value)
          Error(Nil) -> element.none()
        }
      True ->
        html.div([class("intensity-control")], [
          html.input([
            attribute.id("week-intensity"),
            attribute.type_("range"),
            attribute.name("intensity"),
            attribute.attribute("min", "0"),
            attribute.attribute("max", "1"),
            attribute.attribute("step", "0.05"),
            attribute.value(case shown {
              Ok(value) -> float.to_string(value)
              Error(Nil) -> "0"
            }),
            attribute.attribute("aria-valuetext", text),
            attribute.classes([#("unset", shown == Error(Nil))]),
            // How far the active track reaches, for browsers that cannot draw it themselves (ADR 0051).
            attribute.style("--fill", case shown {
              Ok(value) -> plan.intensity_percent(value)
              Error(Nil) -> "0%"
            }),
            event.on_input(IntensityInput),
            event.on_change(IntensityChanged),
          ]),
        ])
    },
  ])
}

fn intensity_bar(value: Float) -> Element(Msg) {
  html.div([class("goal-meter intensity-meter")], [
    html.span([attribute.style("width", plan.intensity_percent(value))], []),
  ])
}

fn distance_text(week: plan_schedule.Week, goal: Option(Float)) -> String {
  let planned = units.format_planned_km(week.distance_m)
  case goal, plan_schedule.goal_share(week, goal) {
    Some(g), Ok(share) ->
      planned
      <> " of "
      <> units.format_planned_km(g)
      <> " ("
      <> int.to_string(float.round(share *. 100.0))
      <> "%)"
    _, _ -> planned
  }
}

fn goal_meter(week: plan_schedule.Week, goal: Option(Float)) -> Element(Msg) {
  case plan_schedule.goal_share(week, goal) {
    Error(Nil) -> element.none()
    Ok(share) ->
      html.div(
        [
          class("goal-meter"),
          attribute.classes([#("over", share >. 1.0)]),
          attribute.role("meter"),
          attribute.attribute("aria-label", "Distance against this week's goal"),
          attribute.attribute(
            "aria-valuenow",
            int.to_string(float.round(share *. 100.0)),
          ),
          attribute.attribute("aria-valuemin", "0"),
          attribute.attribute("aria-valuemax", "100"),
        ],
        [
          html.span(
            [
              attribute.style(
                "width",
                int.to_string(int.min(float.round(share *. 100.0), 100)) <> "%",
              ),
            ],
            [],
          ),
        ],
      )
  }
}

fn workout_count(week: plan_schedule.Week) -> Int {
  week.days
  |> list.flat_map(fn(day) { day.workouts })
  |> list.filter(fn(w) { w.kind != plan.Rest })
  |> list.length
}

/// The delete to write for a workout whose Undo ran out. It is looked up among all the plans' workouts: the user
/// may have opened another plan meanwhile. Whether it could be deleted was checked when Delete was pressed.
fn delete_of(model: Model, id: String) -> List(Action) {
  case find(model.rows, id) {
    Ok(row) -> [Delete(id, row.updated)]
    Error(Nil) -> []
  }
}

fn targets(w: Workout) -> String {
  case w.distance_m, w.duration_s {
    Some(d), Some(t) ->
      units.format_planned_km(d) <> " · " <> units.format_duration(t)
    Some(d), None -> units.format_planned_km(d)
    None, Some(t) -> units.format_duration(t)
    None, None -> ""
  }
}

/// The weeks a workout can be put in: those of the plan, one more after them, and the one in the form.
fn week_options(
  on_screen: Plan,
  weeks: List(plan_schedule.Week),
  current: String,
) -> List(#(String, String)) {
  let last = int.min(list.length(weeks) + 1, workout_form.max_weeks)
  let numbers = case int.parse(current) {
    Ok(n) if n > last && n <= workout_form.max_weeks ->
      list.append(one_to(last), [n])
    _ -> one_to(last)
  }
  list.map(numbers, fn(n) {
    #(int.to_string(n), plan_schedule.week_label(on_screen.phases, n))
  })
}

/// 1, 2, ... n.
fn one_to(n: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, n), fn(_, index) { index + 1 })
}

const form_id = "workout-form"

/// Adding and editing a workout happen in a full-screen dialog (ADR 0057), not in the sidebar.
fn form_view(
  model: Model,
  on_screen: Plan,
  weeks: List(plan_schedule.Week),
  can_edit: Bool,
) -> Element(Msg) {
  let #(open, title) = case can_edit, model.mode {
    True, Adding -> #(True, "New workout")
    True, Editing(_) -> #(True, "Edit workout")
    _, _ -> #(False, "")
  }
  form_dialog.view_with_action(
    "workout-form-dialog",
    open,
    title,
    form_id,
    "Save",
    CancelClicked,
    // A workout is deleted from its form, with Undo (ADR 0056, 0080).
    case can_edit, model.mode {
      True, Editing(id) ->
        button.icon(
          [attribute.type_("button"), event.on_click(DeleteClicked(id))],
          icon.Delete,
          "Delete workout",
        )
      _, _ -> element.none()
    },
    [form_fields(model.form, on_screen, weeks)],
  )
}

fn form_fields(
  form: workout_form.Form,
  on_screen: Plan,
  weeks: List(plan_schedule.Week),
) -> Element(Msg) {
  // A problem shows under the field it is about (ADR 0059).
  let wrong = workout_form.error_field(form)
  let on = fn(help, field_name) {
    field.with_error(help, field_name, wrong, form.error)
  }
  html.form(
    [
      attribute.id(form_id),
      class("workout-form"),
      event.on_submit(fn(_) { Submitted }),
    ],
    [
      field.text(form_title_id, "Title", on(field.plain, "title"), [
        attribute.type_("text"),
        attribute.name("title"),
        attribute.value(form.title),
        attribute.attribute("maxlength", "200"),
        attribute.required(True),
        event.on_input(TitleChanged),
      ]),
      html.div([class("row")], [
        field.choose(
          "workout-week",
          "Week",
          on(field.plain, "week"),
          [attribute.name("week"), event.on_change(WeekChanged)],
          form.week,
          week_options(on_screen, weeks, form.week),
        ),
        field.choose(
          "workout-day",
          "Day",
          on(field.plain, "day"),
          [attribute.name("day"), event.on_change(DayChanged)],
          form.day,
          list.map([1, 2, 3, 4, 5, 6, 7], fn(n) {
            #(int.to_string(n), "Day " <> int.to_string(n))
          }),
        ),
      ]),
      choice.chips(
        "kind",
        "Kind",
        plan.kind_to_string(form.kind),
        list.map(kinds, fn(kind) {
          #(plan.kind_to_string(kind), workout_form.kind_label(kind))
        }),
        KindChanged,
      ),
      html.div([class("row")], [
        field.text(
          "workout-distance",
          "Distance",
          on(field.Help("Optional", "km", None), "distance"),
          [
            attribute.type_("text"),
            attribute.attribute("inputmode", "decimal"),
            attribute.name("distance"),
            attribute.value(form.distance_km),
            event.on_input(DistanceChanged),
          ],
        ),
        field.text(
          "workout-duration",
          "Duration",
          on(
            field.help("Minutes, or hours and minutes: 45 or 1:30"),
            "duration",
          ),
          [
            attribute.type_("text"),
            attribute.name("duration"),
            attribute.value(form.duration),
            event.on_input(DurationChanged),
          ],
        ),
      ]),
      field.area(
        "workout-description",
        "Notes",
        on(field.help("Optional"), "description"),
        [
          attribute.name("description"),
          attribute.rows(3),
          event.on_input(DescriptionChanged),
        ],
        form.description,
      ),
      case form.error, wrong {
        Some(message), "" -> error.message(message)
        _, _ -> element.none()
      },
    ],
  )
}

/// The calendar's main action (ADR 0068), for the plan's owner: a FAB on a phone, a button in the app bar on wider
/// screens. A new workout goes in the week last chosen.
pub fn main_action(
  model: Model,
  on_screen: Plan,
  can_edit: Bool,
) -> Option(button.Main(Msg)) {
  case can_edit, model.mode {
    True, Browsing | True, Viewing(_) -> {
      let weeks =
        plan_schedule.weeks(on_screen.phases, workouts_of(model, on_screen.id))
      Some(button.Main(
        icon.Add,
        "Add workout",
        AddClicked(clamp_week(model.selected_week, weeks), 1),
      ))
    }
    _, _ -> None
  }
}
