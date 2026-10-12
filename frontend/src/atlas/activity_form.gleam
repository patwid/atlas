//// Entering an activity by hand: parsing what the user typed (a local date and time, "8,5" km,
//// "45" minutes) and choosing the fields to write. Pure. A manual activity is stored with its start as a
//// UTC timestamp like all others, so the local date and time are converted with the UTC offset at that moment
//// (ADR 0025). Limits follow the server (ADR 0009).

import atlas/activity.{type Sport}
import atlas/date.{type Date}
import atlas/outbox
import atlas/plan.{type Intervals, type Kind}
import atlas/workout_form
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

const max_name = 200

/// The kinds an activity can be (ADR 0121): those of a workout but a rest day, as resting is not recorded.
pub const kinds = [plan.Run, plan.Interval, plan.Race]

pub type Form {
  Form(
    /// `YYYY-MM-DD`, as a date picker gives it.
    date: String,
    /// `HH:MM`, as a time picker gives it.
    time: String,
    /// The sport as stored; a run for a new activity. One other than a run is offered as a choice of its own.
    stored_sport: Sport,
    /// The sport to save: a run or trail run when a kind is chosen, `stored_sport` when that is kept (ADR 0121).
    sport: Sport,
    /// The title, kind, zone, parts, distance, duration and notes, as in a workout's form (ADR 0121). Its week and
    /// day are not used.
    session: workout_form.Form,
    error: Option(String),
  )
}

/// What a form says after validation. Zeros mean "not given".
pub type Valid {
  Valid(
    day: Date,
    hour: Int,
    minute: Int,
    sport: Sport,
    /// `None` for an activity that keeps a sport other than a run (ADR 0121).
    kind: Option(Kind),
    name: String,
    distance_m: Float,
    duration_s: Int,
    description: String,
    intervals: Option(Intervals),
    zone: Int,
  )
}

/// An activity as stored, with the fields the domain type does not carry.
pub type Row {
  Row(
    activity: activity.Activity,
    owner_id: String,
    name: String,
    elevation_m: Float,
    avg_hr: Int,
    updated: String,
    /// The provider's ID for the activity (Strava's), empty for activities made here.
    external_id: String,
    /// As stored: `None` for an activity saved without one (ADR 0121); see `kind_of`.
    kind: Option(Kind),
    zone: Int,
    intervals: Option(Intervals),
    description: String,
  )
}

pub fn empty_for(today: Date) -> Form {
  Form(
    date.to_string(today),
    "07:00",
    activity.Run,
    activity.Run,
    workout_form.empty_for(1, 1),
    None,
  )
}

/// Whether an activity of this sport has a kind: only runs fulfil a workout (ADR 0114).
pub fn is_running(sport: Sport) -> Bool {
  sport == activity.Run || sport == activity.TrailRun
}

/// The kind of a stored activity: its own, or a run for a run saved without one (ADR 0121). `None` for another sport.
pub fn kind_of(row: Row) -> Option(Kind) {
  case is_running(row.activity.sport), row.kind {
    False, _ -> None
    True, Some(kind) -> Some(kind)
    True, None -> Some(plan.Run)
  }
}

/// The form for editing a stored activity. `offset` is the UTC offset in minutes at its start.
pub fn from_row(row: Row, offset: Int) -> Form {
  let #(day, hour, minute) = case
    date.local_datetime(row.activity.started_at, offset)
  {
    Ok(found) -> found
    Error(Nil) -> #(date.Date(1970, 1, 1), 0, 0)
  }
  let session =
    workout_form.from_row(workout_form.Row(
      workout: plan.Workout(
        id: row.activity.id,
        plan_id: "",
        day_index: 0,
        position: 0,
        title: row.name,
        kind: option.unwrap(kind_of(row), plan.Run),
        distance_m: case row.activity.distance_m >. 0.0 {
          True -> Some(row.activity.distance_m)
          False -> None
        },
        duration_s: case row.activity.moving_time_s > 0 {
          True -> Some(row.activity.moving_time_s)
          False -> None
        },
      ),
      description: row.description,
      intervals: row.intervals,
      zone: row.zone,
      updated: row.updated,
    ))
  Form(
    date: date.to_string(day),
    time: pad2(hour) <> ":" <> pad2(minute),
    stored_sport: row.activity.sport,
    sport: row.activity.sport,
    session: session,
    error: None,
  )
}

/// The value of the Kind choice: the kind, or the sport kept (ADR 0121).
pub fn kind_value(form: Form) -> String {
  case is_running(form.sport) {
    True -> plan.kind_to_string(form.session.kind)
    False -> activity.sport_to_string(form.sport)
  }
}

/// The Kind choice's options: the kinds, then the stored sport when it is not a run.
pub fn kind_options(form: Form) -> List(#(String, String)) {
  let options =
    list.map(kinds, fn(kind) {
      #(plan.kind_to_string(kind), workout_form.kind_label(kind))
    })
  case is_running(form.stored_sport) {
    True -> options
    False ->
      list.append(options, [
        #(
          activity.sport_to_string(form.stored_sport),
          sport_label(form.stored_sport),
        ),
      ])
  }
}

/// A kind or the stored sport was chosen. A kind makes the activity a run, or keeps it a trail run.
pub fn choose(form: Form, value: String) -> Form {
  let kind = list.find(kinds, fn(kind) { plan.kind_to_string(kind) == value })
  let other = !is_running(form.stored_sport)
  case value == activity.sport_to_string(form.stored_sport), kind {
    True, _ if other -> Form(..form, sport: form.stored_sport)
    _, Ok(kind) ->
      Form(
        ..form,
        sport: case form.stored_sport {
          activity.TrailRun -> activity.TrailRun
          _ -> activity.Run
        },
        session: workout_form.Form(..form.session, kind: kind),
      )
    _, Error(Nil) -> form
  }
}

/// Changes the fields shared with a workout's form. Nothing is worked out from a zone or race goal, as in a
/// workout's form: an activity's distances and times were measured (ADR 0121).
pub fn edit(
  form: Form,
  change: fn(workout_form.Form) -> workout_form.Form,
) -> Form {
  Form(..form, session: change(form.session))
}

/// Checks the form; a problem names the field it is about: `date`, `time`, `title`, `distance`, `duration`, or one
/// of a workout's (`workout_form.validate_body`).
pub fn validate_fields(form: Form) -> Result(Valid, #(String, String)) {
  let name = string.trim(form.session.title)
  let running = is_running(form.sport)
  case date.parse(string.trim(form.date)), parse_time(form.time) {
    Error(Nil), _ -> Error(#("date", "Pick the day of the activity."))
    _, Error(Nil) ->
      Error(#(
        "time",
        "Enter the start time as hours and minutes, for example 07:30.",
      ))
    Ok(day), Ok(#(hour, minute)) ->
      case day.year < 2000 || day.year > 2100 {
        True ->
          Error(#("date", "The date must be between the years 2000 and 2100."))
        False ->
          case string.length(name) > max_name {
            True ->
              Error(#("title", "The title can have at most 200 characters."))
            False -> {
              // Another sport has no zone or parts (ADR 0121).
              let session = case running {
                True -> form.session
                False ->
                  workout_form.Form(..form.session, kind: plan.Run, zone: "")
              }
              use body <- result.try(workout_form.validate_body(session))
              // A distance or duration left empty is that of the parts, for intervals.
              let #(total_distance, total_time) = case session.kind {
                plan.Interval -> workout_form.interval_totals(session)
                _ -> #(None, None)
              }
              let distance_m = case body.distance_m >. 0.0, total_distance {
                False, Some(m) -> m
                _, _ -> body.distance_m
              }
              let duration_s = case body.duration_s > 0, total_time {
                False, Some(s) -> s
                _, _ -> body.duration_s
              }
              case distance_m <=. 0.0 && duration_s <= 0 {
                True ->
                  Error(#(
                    "distance",
                    "Enter a distance or a duration, or both.",
                  ))
                False ->
                  Ok(Valid(
                    day: day,
                    hour: hour,
                    minute: minute,
                    sport: form.sport,
                    kind: case running {
                      True -> Some(session.kind)
                      False -> None
                    },
                    name: name,
                    distance_m: distance_m,
                    duration_s: duration_s,
                    description: body.description,
                    intervals: body.intervals,
                    zone: body.zone,
                  ))
              }
            }
          }
      }
  }
}

/// `07:30` (also `7:30`) to hours and minutes.
pub fn parse_time(text: String) -> Result(#(Int, Int), Nil) {
  case string.split(string.trim(text), ":") {
    [h, m] ->
      case int.parse(h), int.parse(m), string.length(m) {
        Ok(hour), Ok(minute), 2
          if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
        -> Ok(#(hour, minute))
        _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

// FIELDS TO WRITE ---------------------------------------------------------------------------------

/// The fields of a new manual activity. `offset` is the UTC offset in minutes on that day and time.
pub fn create_fields(
  owner_id: String,
  valid: Valid,
  offset: Int,
) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("owner", owner_id),
    outbox.field_string("source", "manual"),
    ..value_fields(valid, offset)
  ])
}

/// Only what differs from the stored activity. Empty when nothing changed.
pub fn changed_fields(row: Row, valid: Valid, offset: Int) -> outbox.Fields {
  let a = row.activity
  value_fields(valid, offset)
  |> list.filter(fn(field) {
    case field.0 {
      "started_at" ->
        field.1 != outbox.field_string("started_at", a.started_at).1
      "sport" -> valid.sport != a.sport
      "kind" -> valid.kind != kind_of(row)
      "name" -> valid.name != row.name
      "distance_m" -> valid.distance_m != a.distance_m
      "moving_time_s" -> valid.duration_s != a.moving_time_s
      "elapsed_time_s" -> valid.duration_s != a.moving_time_s
      "zone" -> valid.zone != row.zone
      "steps" -> valid.intervals != row.intervals
      "description" -> valid.description != row.description
      _ -> False
    }
  })
  |> dict.from_list
}

fn value_fields(valid: Valid, offset: Int) -> List(#(String, String)) {
  [
    outbox.field_string(
      "started_at",
      date.utc_timestamp(valid.day, valid.hour, valid.minute, offset),
    ),
    outbox.field_string("sport", activity.sport_to_string(valid.sport)),
    outbox.field_string("kind", case valid.kind {
      Some(kind) -> plan.kind_to_string(kind)
      None -> ""
    }),
    outbox.field_string("name", valid.name),
    outbox.field_float("distance_m", valid.distance_m),
    outbox.field_int("moving_time_s", valid.duration_s),
    outbox.field_int("elapsed_time_s", valid.duration_s),
    outbox.field_int("zone", valid.zone),
    workout_form.steps_field(valid.intervals),
    outbox.field_string("description", valid.description),
  ]
}

/// What an activity is called without a title, and after its date with one: its sport for a run, as it may be a
/// trail run, else its kind or sport (ADR 0121).
pub fn type_label(row: Row) -> String {
  case kind_of(row) {
    Some(plan.Interval) | Some(plan.Race) | Some(plan.Rest) ->
      workout_form.kind_label(option.unwrap(kind_of(row), plan.Run))
    Some(plan.Run) | None -> sport_label(row.activity.sport)
  }
}

/// The zone, or the parts of intervals, or a race's warm-up, zone and cool-down, as a workout shows them (ADR 0121);
/// `""` without any.
pub fn targets(row: Row) -> String {
  case kind_of(row), row.intervals {
    None, _ -> []
    Some(plan.Interval), Some(intervals) -> [
      workout_form.intervals_summary(intervals),
    ]
    Some(plan.Race), Some(intervals) -> [
      workout_form.warmup_summary(intervals),
      workout_form.zone_label(row.zone),
      workout_form.cooldown_summary(intervals),
    ]
    Some(_), _ -> [workout_form.zone_label(row.zone)]
  }
  |> list.filter(fn(part) { part != "" })
  |> string.join(" · ")
}

pub fn sport_label(sport: Sport) -> String {
  case sport {
    activity.Run -> "Run"
    activity.TrailRun -> "Trail run"
    activity.Walk -> "Walk"
    activity.Hike -> "Hike"
    activity.Ride -> "Ride"
    activity.Swim -> "Swim"
    activity.Strength -> "Strength"
    activity.Other -> "Other"
  }
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}

/// The address of a Strava activity on strava.com, for the "View on Strava" link that Strava's brand rules
/// require wherever its data is shown (ADR 0027). `None` for anything that did not come from Strava, and for
/// an ID that is not just digits, so that nothing but a number ever reaches the address.
pub fn strava_url(row: Row) -> Option(String) {
  case row.activity.source, row.external_id {
    activity.Strava, id if id != "" ->
      case string.to_graphemes(id) |> list.all(is_digit) {
        True -> Some("https://www.strava.com/activities/" <> id)
        False -> None
      }
    _, _ -> None
  }
}

fn is_digit(character: String) -> Bool {
  string.contains("0123456789", character)
}

/// The form's problem without the field it is about (ADR 0059).
pub fn validate(form: Form) -> Result(Valid, String) {
  validate_fields(form) |> result.map_error(fn(problem) { problem.1 })
}

/// The field the form's problem is about, `""` when there is none: its error is shown under that field (ADR 0059).
pub fn error_field(form: Form) -> String {
  case validate_fields(form) {
    Error(#(field, _)) -> field
    Ok(_) -> ""
  }
}
