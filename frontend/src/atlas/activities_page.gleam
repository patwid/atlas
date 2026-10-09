//// The activities screen: the user's recorded sessions, with a form to add one by hand and to change or
//// remove those that are theirs to change. Strava activities are shown but cannot be edited here (ADR 0005,
//// 0009). Own state and messages; writes come back as `Action`s (ADR 0020, 0025).

import atlas/activity.{type Source}
import atlas/activity_form.{type Row}
import atlas/collection
import atlas/date.{type Date}
import atlas/outbox
import atlas/random
import atlas/records
import atlas/route
import atlas/store
import atlas/ui/button
import atlas/ui/chip
import atlas/ui/choice
import atlas/ui/date_picker
import atlas/ui/empty
import atlas/ui/error
import atlas/ui/field
import atlas/ui/focus
import atlas/ui/form_dialog
import atlas/ui/icon
import atlas/ui/layout
import atlas/ui/progress
import atlas/ui/time_picker
import atlas/ui/undo.{type Undo}
import atlas/units
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
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
    /// Every activity on the device, including those of athletes the user coaches.
    rows: List(Row),
    loaded: Bool,
    mode: Mode,
    form: activity_form.Form,
    /// A delete that can still be undone (ADR 0056).
    undo: Undo,
    /// The form's date and time pickers (ADR 0054).
    date_picker: date_picker.State,
    time_picker: time_picker.State,
  )
}

/// What the screen needs that is not its own state. The offsets are functions because the UTC offset
/// depends on the date (daylight saving): the browser knows, this module only asks.
pub type Context {
  Context(
    user_id: String,
    today: Date,
    /// The UTC offset in minutes at a local date and time.
    offset_at_local: fn(Date, Int, Int) -> Int,
    /// The UTC offset in minutes that applied at a UTC timestamp.
    offset_at_utc: fn(String) -> Int,
  )
}

pub type Msg {
  Refresh
  ActivitiesRead(Result(List(Dynamic), Nil))
  AddClicked
  EditClicked(String)
  CancelClicked
  DateChanged(String)
  TimeChanged(String)
  /// A picker's button was pressed; it opens on what the field holds now (ADR 0054).
  DatePickerOpened
  TimePickerOpened
  DatePicker(date_picker.Msg)
  TimePicker(time_picker.Msg)
  SportChanged(String)
  NameChanged(String)
  DistanceChanged(String)
  DurationChanged(String)
  ElevationChanged(String)
  HeartRateChanged(String)
  Submitted
  /// Deletes at once, with Undo for a few seconds (ADR 0056).
  DeleteClicked(String)
  UndoClicked
  /// The Undo snackbar went: the delete with this number is written.
  DeleteExpired(Int)
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
    activity_form.empty_for(date.Date(2026, 1, 1)),
    undo.new(),
    date_picker.new(),
    time_picker.new(),
  )
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Activities, fn(result) {
      dispatch(ActivitiesRead(result))
    })
  })
}

/// The user's own activities, newest first.
pub fn mine(model: Model, user_id: String) -> List(Row) {
  model.rows
  |> list.filter(fn(row) { row.owner_id == user_id })
  |> list.sort(fn(a, b) {
    order.lazy_break_tie(
      string.compare(b.activity.started_at, a.activity.started_at),
      fn() { string.compare(a.activity.id, b.activity.id) },
    )
  })
}

/// Clients may change manual and file-imported activities of their own (the server's rule, 0009).
pub fn editable(row: Row, user_id: String) -> Bool {
  row.owner_id == user_id
  && case row.activity.source {
    activity.Manual | activity.Fit -> True
    activity.Strava | activity.Garmin -> False
  }
}

pub fn update(
  model: Model,
  msg: Msg,
  context: Context,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    ActivitiesRead(Ok(stored)) -> {
      let rows = records.live(stored, records.activity_row)
      let mode = case model.mode {
        Editing(id) ->
          case list.any(rows, fn(row) { row.activity.id == id }) {
            True -> model.mode
            False -> Browsing
          }
        other -> other
      }
      #(Model(..model, rows: rows, loaded: True, mode: mode), effect.none(), [])
    }
    ActivitiesRead(Error(Nil)) -> #(model, effect.none(), [])

    AddClicked -> #(
      Model(..model, mode: Adding, form: activity_form.empty_for(context.today)),
      // The form opens in a dialog (ADR 0057); its first field takes the focus.
      focus.soon("activity-date"),
      [],
    )

    EditClicked(id) ->
      case find(mine(model, context.user_id), id) {
        Ok(row) ->
          case editable(row, context.user_id) {
            True -> #(
              Model(
                ..model,
                mode: Editing(id),
                form: activity_form.from_row(
                  row,
                  context.offset_at_utc(row.activity.started_at),
                ),
              ),
              effect.none(),
              [],
            )
            False -> #(model, effect.none(), [])
          }
        Error(Nil) -> #(model, effect.none(), [])
      }

    CancelClicked -> #(Model(..model, mode: Browsing), effect.none(), [])

    DateChanged(v) -> typed(model, fn(f) { activity_form.Form(..f, date: v) })
    TimeChanged(v) -> typed(model, fn(f) { activity_form.Form(..f, time: v) })
    DatePickerOpened ->
      update(
        model,
        DatePicker(date_picker.Opened(model.form.date, context.today)),
        context,
      )
    TimePickerOpened ->
      update(model, TimePicker(time_picker.Opened(model.form.time)), context)
    DatePicker(inner) -> {
      let #(state, picker_effect, picked) =
        date_picker.update(date_picker_id, model.date_picker, inner)
      let model = Model(..model, date_picker: state)
      let #(model, _, _) = case picked {
        Some(v) -> typed(model, fn(f) { activity_form.Form(..f, date: v) })
        None -> #(model, effect.none(), [])
      }
      #(model, effect.map(picker_effect, DatePicker), [])
    }
    TimePicker(inner) -> {
      let #(state, picker_effect, picked) =
        time_picker.update(time_picker_id, model.time_picker, inner)
      let model = Model(..model, time_picker: state)
      let #(model, _, _) = case picked {
        Some(v) -> typed(model, fn(f) { activity_form.Form(..f, time: v) })
        None -> #(model, effect.none(), [])
      }
      #(model, effect.map(picker_effect, TimePicker), [])
    }
    SportChanged(v) ->
      typed(model, fn(f) {
        case activity.sport_from_string(v) {
          Ok(sport) -> activity_form.Form(..f, sport: sport)
          Error(Nil) -> f
        }
      })
    NameChanged(v) -> typed(model, fn(f) { activity_form.Form(..f, name: v) })
    DistanceChanged(v) ->
      typed(model, fn(f) { activity_form.Form(..f, distance_km: v) })
    DurationChanged(v) ->
      typed(model, fn(f) { activity_form.Form(..f, duration: v) })
    ElevationChanged(v) ->
      typed(model, fn(f) { activity_form.Form(..f, elevation_m: v) })
    HeartRateChanged(v) ->
      typed(model, fn(f) { activity_form.Form(..f, avg_hr: v) })

    Submitted ->
      case activity_form.validate(model.form) {
        Error(message) -> #(
          Model(
            ..model,
            form: activity_form.Form(..model.form, error: Some(message)),
          ),
          effect.none(),
          [],
        )
        Ok(valid) -> {
          let offset =
            context.offset_at_local(valid.day, valid.hour, valid.minute)
          let finished = Model(..model, mode: Browsing)
          case model.mode {
            Adding -> #(finished, effect.none(), [
              Create(
                random.new_id(),
                activity_form.create_fields(context.user_id, valid, offset),
              ),
            ])
            Editing(id) ->
              case find(mine(model, context.user_id), id) {
                Ok(row) -> {
                  let fields = activity_form.changed_fields(row, valid, offset)
                  #(
                    finished,
                    effect.none(),
                    case
                      dict.is_empty(fields) || !editable(row, context.user_id)
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

    DeleteClicked(id) ->
      case delete_of(model, context, id) {
        [] -> #(model, effect.none(), [])
        _ -> {
          let #(next, earlier, wait) = undo.start(model.undo, id, DeleteExpired)
          #(
            Model(..model, undo: next, mode: Browsing),
            wait,
            option.map(earlier, delete_of(model, context, _))
              |> option.unwrap([]),
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
        option.map(due, delete_of(model, context, _)) |> option.unwrap([]),
      )
    }
  }
}

fn typed(
  model: Model,
  change: fn(activity_form.Form) -> activity_form.Form,
) -> #(Model, Effect(Msg), List(Action)) {
  let changed = change(model.form)
  #(
    Model(..model, form: activity_form.Form(..changed, error: None)),
    effect.none(),
    [],
  )
}

fn find(rows: List(Row), id: String) -> Result(Row, Nil) {
  list.find(rows, fn(row) { row.activity.id == id })
}

// VIEWS -------------------------------------------------------------------------------------------

const sports = [
  activity.Run,
  activity.TrailRun,
  activity.Walk,
  activity.Hike,
  activity.Ride,
  activity.Swim,
  activity.Strength,
  activity.Other,
]

pub fn view(model: Model, context: Context) -> Element(Msg) {
  let rows = mine(model, context.user_id)
  html.section([class("activities")], [
    undo.snackbar(model.undo, "Activity deleted", UndoClicked, DeleteExpired),
    html.div([class("toolbar")], [
      button.fab_for(main_action(model)),
    ]),
    form_view(model, context.today),
    case model.loaded, rows {
      False, _ -> progress.loading("Loading…")
      True, [] ->
        case model.mode {
          Adding -> element.none()
          _ ->
            empty.view(
              icon.DirectionsRun,
              "No activities yet",
              "Add one, or connect Strava to bring them in.",
              Some(empty.link(
                route.to_path(route.SettingsPage(route.Strava)),
                "Connect Strava",
              )),
            )
        }
      True, _ ->
        layout.list(
          rows
          |> list.filter(fn(row) { !undo.hides(model.undo, row.activity.id) })
          |> list.map(fn(row) { row_view(row, context) }),
        )
    },
  ])
}

fn row_view(row: Row, context: Context) -> Element(Msg) {
  let a = row.activity
  html.li([], [
    html.div([], [
      // An activity the user can change opens in its form from anywhere on its row (ADR 0080).
      case editable(row, context.user_id) {
        True ->
          html.button(
            [
              attribute.type_("button"),
              class("row-link"),
              attribute.attribute("aria-haspopup", "dialog"),
              event.on_click(EditClicked(a.id)),
            ],
            [html.text(title(row))],
          )
        False -> html.strong([], [html.text(title(row))])
      },
      chip.row([
        source_chip(a.source),
        case row.updated {
          "" -> chip.with_icon(icon.CloudUpload, "Not synced yet")
          _ -> element.none()
        },
      ]),
    ]),
    html.p([class("muted")], [html.text(when(row, context))]),
    case figures(row) {
      "" -> element.none()
      text -> html.p([class("figures")], [html.text(text)])
    },
    view_on_strava(row),
  ])
}

/// Strava's brand rules: wherever its data is shown, link back to it with exactly this text (ADR 0027).
pub fn view_on_strava(row: Row) -> Element(msg) {
  case activity_form.strava_url(row) {
    Some(url) ->
      html.p([], [
        html.a(
          [
            attribute.href(url),
            attribute.target("_blank"),
            attribute.rel("noopener noreferrer"),
            class("strava-link"),
          ],
          [html.text("View on Strava")],
        ),
      ])
    None -> element.none()
  }
}

fn title(row: Row) -> String {
  case row.name {
    "" -> activity_form.sport_label(row.activity.sport)
    name -> name
  }
}

/// Where an activity came from, a connected service or a file (ADR 0050). Most are entered by hand, so those
/// have no chip (ADR 0074).
fn source_chip(source: Source) -> Element(Msg) {
  case source {
    activity.Manual -> element.none()
    activity.Strava | activity.Garmin ->
      chip.with_icon(icon.Link, source_label(source))
    activity.Fit -> chip.label(source_label(source))
  }
}

fn source_label(source: Source) -> String {
  case source {
    activity.Strava -> "Strava"
    activity.Manual -> "Added by hand"
    activity.Fit -> "From a file"
    activity.Garmin -> "Garmin"
  }
}

/// `Thu 1 Oct 2026, 07:30 · Run`, in the user's local time. The sport is left out when it is already the title.
fn when(row: Row, context: Context) -> String {
  let offset = context.offset_at_utc(row.activity.started_at)
  let moment = case date.local_datetime(row.activity.started_at, offset) {
    Ok(#(day, hour, minute)) ->
      date.format(day) <> ", " <> pad2(hour) <> ":" <> pad2(minute)
    Error(Nil) -> "Unknown time"
  }
  case row.name {
    "" -> moment
    _ -> moment <> " · " <> activity_form.sport_label(row.activity.sport)
  }
}

fn figures(row: Row) -> String {
  let a = row.activity
  let parts =
    [
      case a.distance_m >. 0.0 {
        True -> units.format_distance_km(a.distance_m)
        False -> ""
      },
      case a.moving_time_s > 0 {
        True -> units.format_duration(a.moving_time_s)
        False -> ""
      },
      case pace(a) {
        Some(text) -> text
        None -> ""
      },
      case row.elevation_m >. 0.0 {
        True -> "↑ " <> int.to_string(float.round(row.elevation_m)) <> " m"
        False -> ""
      },
      case row.avg_hr > 0 {
        True -> int.to_string(row.avg_hr) <> " bpm"
        False -> ""
      },
    ]
    |> list.filter(fn(part) { part != "" })
  string.join(parts, " · ")
}

/// A pace only makes sense for sports people run or walk.
fn pace(a: activity.Activity) -> Option(String) {
  case a.sport {
    activity.Run | activity.TrailRun | activity.Walk | activity.Hike ->
      case units.pace_seconds_per_km(a.distance_m, a.moving_time_s) {
        Ok(seconds) -> Some(units.format_pace(seconds))
        Error(Nil) -> None
      }
    _ -> None
  }
}

/// The delete to write for `id`: none unless it is the user's own activity, entered by hand.
fn delete_of(model: Model, context: Context, id: String) -> List(Action) {
  case find(mine(model, context.user_id), id) {
    Ok(row) ->
      case editable(row, context.user_id) {
        True -> [Delete(id, row.updated)]
        False -> []
      }
    Error(Nil) -> []
  }
}

const date_picker_id = "activity-date-picker"

const time_picker_id = "activity-time-picker"

const form_id = "activity-form"

/// Adding and editing happen in a full-screen dialog (ADR 0057).
fn form_view(model: Model, today: Date) -> Element(Msg) {
  let #(open, title, submit_label) = case model.mode {
    Adding -> #(True, "New activity", "Save")
    Editing(_) -> #(True, "Edit activity", "Save")
    Browsing -> #(False, "", "")
  }
  form_dialog.view_with_action(
    "activity-form-dialog",
    open,
    title,
    form_id,
    submit_label,
    CancelClicked,
    // An activity is deleted from its form, with Undo (ADR 0056, 0080).
    case model.mode {
      Editing(id) ->
        button.icon(
          [attribute.type_("button"), event.on_click(DeleteClicked(id))],
          icon.Delete,
          "Delete activity",
        )
      _ -> element.none()
    },
    // The pickers' dialogs hold forms of their own, so they sit beside this form, not in it.
    [
      form_fields(model.form),
      date_picker.view(date_picker_id, model.date_picker, today, DatePicker),
      time_picker.view(time_picker_id, model.time_picker, TimePicker),
    ],
  )
}

fn form_fields(form: activity_form.Form) -> Element(Msg) {
  // A problem shows under the field it is about (ADR 0059).
  let wrong = activity_form.error_field(form)
  let on = fn(help, field_name) {
    field.with_error(help, field_name, wrong, form.error)
  }
  html.form(
    [
      attribute.id(form_id),
      class("activity-form"),
      event.on_submit(fn(_) { Submitted }),
    ],
    [
      html.div([class("row")], [
        field.with_trigger(
          field.text("activity-date", "Day", on(field.plain, "date"), [
            attribute.type_("date"),
            attribute.name("date"),
            attribute.value(form.date),
            attribute.required(True),
            event.on_input(DateChanged),
          ]),
          date_picker.trigger(date_picker_id, DatePickerOpened),
        ),
        field.with_trigger(
          field.text("activity-time", "Start time", on(field.plain, "time"), [
            attribute.type_("time"),
            attribute.name("time"),
            attribute.value(form.time),
            attribute.required(True),
            event.on_input(TimeChanged),
          ]),
          time_picker.trigger(time_picker_id, TimePickerOpened),
        ),
      ]),
      choice.chips(
        "sport",
        "Sport",
        activity.sport_to_string(form.sport),
        list.map(sports, fn(sport) {
          #(activity.sport_to_string(sport), activity_form.sport_label(sport))
        }),
        SportChanged,
      ),
      html.div([class("row")], [
        field.text(
          "activity-distance",
          "Distance",
          // One of the two is needed: said up front rather than only once Save is pressed.
          on(
            field.Help("A distance, a duration or both", "km", None),
            "distance",
          ),
          [
            attribute.type_("text"),
            attribute.attribute("inputmode", "decimal"),
            attribute.name("distance"),
            attribute.value(form.distance_km),
            event.on_input(DistanceChanged),
          ],
        ),
        field.text(
          "activity-duration",
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
      // What is not needed is a group of its own, after what is (ADR 0085).
      layout.subheader("Optional"),
      field.text("activity-name", "Name", on(field.plain, "name"), [
        attribute.type_("text"),
        attribute.name("name"),
        attribute.value(form.name),
        attribute.attribute("maxlength", "200"),
        event.on_input(NameChanged),
      ]),
      html.div([class("row")], [
        field.text(
          "activity-elevation",
          "Climb",
          on(field.suffix("m"), "elevation"),
          [
            attribute.type_("text"),
            attribute.attribute("inputmode", "numeric"),
            attribute.name("elevation"),
            attribute.value(form.elevation_m),
            event.on_input(ElevationChanged),
          ],
        ),
        field.text(
          "activity-hr",
          "Average heart rate",
          on(field.suffix("bpm"), "avg_hr"),
          [
            attribute.type_("text"),
            attribute.attribute("inputmode", "numeric"),
            attribute.name("heart_rate"),
            attribute.value(form.avg_hr),
            event.on_input(HeartRateChanged),
          ],
        ),
      ]),
      // A problem that is about no single field shows at the end.
      case form.error, wrong {
        Some(message), "" -> error.message(message)
        _, _ -> element.none()
      },
    ],
  )
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}

/// The activities' main action (ADR 0068): a FAB on a phone, a button in the app bar on wider screens.
pub fn main_action(model: Model) -> Option(button.Main(Msg)) {
  case model.mode {
    Browsing -> Some(button.Main(icon.Add, "Add activity", AddClicked))
    _ -> None
  }
}
