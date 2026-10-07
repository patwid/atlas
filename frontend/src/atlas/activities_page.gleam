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
import atlas/store
import atlas/ui/button
import atlas/ui/dialog
import atlas/ui/error
import atlas/ui/field
import atlas/ui/layout
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
    confirming: Option(String),
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
  SportChanged(String)
  NameChanged(String)
  DistanceChanged(String)
  DurationChanged(String)
  ElevationChanged(String)
  HeartRateChanged(String)
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
  Model(
    [],
    False,
    Browsing,
    activity_form.empty_for(date.Date(2026, 1, 1)),
    None,
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
      Model(
        ..model,
        mode: Adding,
        form: activity_form.empty_for(context.today),
        confirming: None,
      ),
      effect.none(),
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

    DateChanged(v) -> typed(model, fn(f) { activity_form.Form(..f, date: v) })
    TimeChanged(v) -> typed(model, fn(f) { activity_form.Form(..f, time: v) })
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

    DeleteClicked(id) -> #(
      Model(..model, confirming: Some(id)),
      dialog.show(confirm_dialog_id(id)),
      [],
    )

    DeleteConfirmed(id) ->
      case find(mine(model, context.user_id), id) {
        Ok(row) ->
          case editable(row, context.user_id) {
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
    html.div([class("toolbar")], [
      html.h2([], [html.text("Your activities")]),
      case model.mode {
        Browsing ->
          button.primary(
            [attribute.type_("button"), event.on_click(AddClicked)],
            [html.text("Add activity")],
          )
        _ -> element.none()
      },
    ]),
    case model.mode {
      Adding -> form_view(model.form, "Save activity")
      _ -> element.none()
    },
    case model.loaded, rows {
      False, _ -> html.p([class("muted")], [html.text("Loading…")])
      True, [] ->
        case model.mode {
          Adding -> element.none()
          _ ->
            html.p([class("muted")], [
              html.text(
                "No activities yet. Add one, or connect Strava to bring them in.",
              ),
            ])
        }
      True, _ ->
        html.ul(
          [class("cards")],
          list.map(rows, fn(row) { row_view(row, model, context) }),
        )
    },
  ])
}

fn row_view(row: Row, model: Model, context: Context) -> Element(Msg) {
  let a = row.activity
  html.li([], [
    case model.mode {
      Editing(editing) if editing == a.id ->
        form_view(model.form, "Save changes")
      _ ->
        html.div([], [
          html.div([], [
            html.strong([], [html.text(title(row))]),
            html.span([class("badges")], [
              html.span([class("badge")], [html.text(source_label(a.source))]),
              case row.updated {
                "" -> html.span([class("badge")], [html.text("Not synced yet")])
                _ -> element.none()
              },
            ]),
          ]),
          html.p([class("muted")], [html.text(when(row, context))]),
          case figures(row) {
            "" -> element.none()
            text -> html.p([], [html.text(text)])
          },
          view_on_strava(row),
          case editable(row, context.user_id) {
            False -> element.none()
            True -> actions(row)
          },
        ])
    },
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

fn source_label(source: Source) -> String {
  case source {
    activity.Strava -> "Strava"
    activity.Manual -> "Added by hand"
    activity.Fit -> "From a file"
    activity.Garmin -> "Garmin"
  }
}

/// `Thu 1 Oct 2026, 07:30 · Run`, in the user's local time.
fn when(row: Row, context: Context) -> String {
  let offset = context.offset_at_utc(row.activity.started_at)
  let moment = case date.local_datetime(row.activity.started_at, offset) {
    Ok(#(day, hour, minute)) ->
      date.format(day) <> ", " <> pad2(hour) <> ":" <> pad2(minute)
    Error(Nil) -> "Unknown time"
  }
  moment <> " · " <> activity_form.sport_label(row.activity.sport)
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

fn confirm_dialog_id(id: String) -> String {
  "confirm-delete-activity-" <> id
}

fn actions(row: Row) -> Element(Msg) {
  let id = row.activity.id
  layout.actions([
    button.secondary(
      [attribute.type_("button"), event.on_click(EditClicked(id))],
      [html.text("Edit")],
    ),
    button.secondary(
      [attribute.type_("button"), event.on_click(DeleteClicked(id))],
      [html.text("Delete")],
    ),
    dialog.view(confirm_dialog_id(id), "Delete this activity?", CancelClicked, [
      button.danger(
        [attribute.type_("submit"), event.on_click(DeleteConfirmed(id))],
        [html.text("Yes, delete it")],
      ),
      button.secondary(
        [attribute.type_("submit"), event.on_click(CancelClicked)],
        [html.text("Keep it")],
      ),
    ]),
  ])
}

fn form_view(form: activity_form.Form, submit_label: String) -> Element(Msg) {
  html.form([class("activity-form"), event.on_submit(fn(_) { Submitted })], [
    html.div([class("row")], [
      html.div([], [
        html.label([attribute.for("activity-date")], [html.text("Day")]),
        field.input([
          attribute.id("activity-date"),
          attribute.type_("date"),
          attribute.name("date"),
          attribute.value(form.date),
          attribute.required(True),
          event.on_input(DateChanged),
        ]),
      ]),
      html.div([], [
        html.label([attribute.for("activity-time")], [html.text("Start time")]),
        field.input([
          attribute.id("activity-time"),
          attribute.type_("time"),
          attribute.name("time"),
          attribute.value(form.time),
          attribute.required(True),
          event.on_input(TimeChanged),
        ]),
      ]),
    ]),
    html.label([attribute.for("activity-sport")], [html.text("Sport")]),
    field.select(
      [
        attribute.id("activity-sport"),
        attribute.name("sport"),
        attribute.value(activity.sport_to_string(form.sport)),
        event.on_change(SportChanged),
      ],
      list.map(sports, fn(sport) {
        html.option(
          [attribute.value(activity.sport_to_string(sport))],
          activity_form.sport_label(sport),
        )
      }),
    ),
    html.label([attribute.for("activity-name")], [html.text("Name (optional)")]),
    field.input([
      attribute.id("activity-name"),
      attribute.type_("text"),
      attribute.name("name"),
      attribute.value(form.name),
      attribute.attribute("maxlength", "200"),
      event.on_input(NameChanged),
    ]),
    html.div([class("row")], [
      html.div([], [
        html.label([attribute.for("activity-distance")], [
          html.text("Distance (km)"),
        ]),
        field.input([
          attribute.id("activity-distance"),
          attribute.type_("text"),
          attribute.attribute("inputmode", "decimal"),
          attribute.name("distance"),
          attribute.value(form.distance_km),
          attribute.placeholder("8.5"),
          event.on_input(DistanceChanged),
        ]),
      ]),
      html.div([], [
        html.label([attribute.for("activity-duration")], [
          html.text("Time (minutes or h:mm)"),
        ]),
        field.input([
          attribute.id("activity-duration"),
          attribute.type_("text"),
          attribute.name("duration"),
          attribute.value(form.duration),
          attribute.placeholder("45 or 1:30"),
          event.on_input(DurationChanged),
        ]),
      ]),
    ]),
    html.div([class("row")], [
      html.div([], [
        html.label([attribute.for("activity-elevation")], [
          html.text("Climb (m, optional)"),
        ]),
        field.input([
          attribute.id("activity-elevation"),
          attribute.type_("text"),
          attribute.attribute("inputmode", "numeric"),
          attribute.name("elevation"),
          attribute.value(form.elevation_m),
          event.on_input(ElevationChanged),
        ]),
      ]),
      html.div([], [
        html.label([attribute.for("activity-hr")], [
          html.text("Average heart rate (optional)"),
        ]),
        field.input([
          attribute.id("activity-hr"),
          attribute.type_("text"),
          attribute.attribute("inputmode", "numeric"),
          attribute.name("heart_rate"),
          attribute.value(form.avg_hr),
          event.on_input(HeartRateChanged),
        ]),
      ]),
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

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}
