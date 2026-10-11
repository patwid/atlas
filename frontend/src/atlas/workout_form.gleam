//// The workout form: parsing what the user typed (a week, a day, "5,5" km, "1:30" hours) and choosing
//// which fields to write. Pure. Limits follow the server (ADR 0009).

import atlas/outbox
import atlas/plan.{type Intervals, type Kind, type Workout, Intervals}
import gleam/dict
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const max_title = 200

pub const max_description = 5000

/// Plans can run for a year or so; the limit keeps typing mistakes (week 5000) out.
pub const max_weeks = 60

const max_distance_km = 1000.0

const max_duration_seconds = 172_800

pub const max_reps = 100

const max_rep_distance_m = 20_000.0

const max_rep_seconds = 3600

/// The training zones of the athlete's settings: five of each kind (ADR 0034, 0035, 0036).
pub const zones = [1, 2, 3, 4, 5]

pub type Form {
  Form(
    /// 1-based, as typed.
    week: String,
    /// 1-7, the day of the plan's week.
    day: String,
    title: String,
    kind: Kind,
    distance_km: String,
    duration: String,
    description: String,
    /// The repetitions of an interval workout, as typed; only read when the kind is intervals (ADR 0104).
    reps: String,
    /// Metres.
    rep_distance: String,
    /// Seconds, or minutes and seconds: `90`, `1:30`.
    rep_time: String,
    recovery: String,
    /// The target zone, `""` for none (ADR 0105).
    zone: String,
    error: Option(String),
  )
}

/// What a form says after validation. A distance or duration of 0 means "no target".
pub type Valid {
  Valid(
    day_index: Int,
    title: String,
    kind: Kind,
    distance_m: Float,
    duration_s: Int,
    description: String,
    /// `None` unless the workout is an interval workout with repetitions.
    intervals: Option(Intervals),
    /// 1-5, 0 for none (ADR 0105).
    zone: Int,
  )
}

/// A workout as stored, with the fields the domain type does not carry.
pub type Row {
  Row(
    workout: Workout,
    description: String,
    intervals: Option(Intervals),
    zone: Int,
    updated: String,
  )
}

pub fn empty_for(week: Int, day: Int) -> Form {
  Form(
    int.to_string(week),
    int.to_string(day),
    "",
    plan.Easy,
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    None,
  )
}

pub fn from_row(row: Row) -> Form {
  let w = row.workout
  Form(
    week: int.to_string(w.day_index / 7 + 1),
    day: int.to_string(w.day_index % 7 + 1),
    title: w.title,
    kind: w.kind,
    distance_km: case w.distance_m {
      Some(m) -> format_km(m)
      None -> ""
    },
    duration: case w.duration_s {
      Some(s) -> format_duration(s)
      None -> ""
    },
    description: row.description,
    reps: case row.intervals {
      Some(i) -> int.to_string(i.reps)
      None -> ""
    },
    rep_distance: case row.intervals {
      Some(i) if i.rep_distance_m >. 0.0 ->
        int.to_string(float.round(i.rep_distance_m))
      _ -> ""
    },
    rep_time: case row.intervals {
      Some(i) if i.rep_s > 0 -> format_rep_time(i.rep_s)
      _ -> ""
    },
    recovery: case row.intervals {
      Some(i) if i.recovery_s > 0 -> format_rep_time(i.recovery_s)
      _ -> ""
    },
    zone: case row.zone {
      0 -> ""
      n -> int.to_string(n)
    },
    error: None,
  )
}

/// Checks the form; a problem names the field it is about: `week`, `day`, `title`, `description`, `distance`,
/// `duration`, `reps`, `rep_distance`, `rep_time`, `recovery` or `zone`.
pub fn validate_fields(form: Form) -> Result(Valid, #(String, String)) {
  let title = string.trim(form.title)
  let description = string.trim(form.description)
  case
    int.parse(string.trim(form.week)),
    int.parse(string.trim(form.day)),
    string.length(title)
  {
    Error(_), _, _ -> Error(#("week", "Enter the week as a number."))
    Ok(week), _, _ if week < 1 || week > max_weeks ->
      Error(#("week", "The week must be between 1 and 60."))
    _, Error(_), _ -> Error(#("day", "Choose the day of the week."))
    _, Ok(day), _ if day < 1 || day > 7 ->
      Error(#("day", "The day must be between 1 and 7."))
    _, _, 0 -> Error(#("title", "Give the workout a title."))
    _, _, n if n > max_title ->
      Error(#("title", "The title can have at most 200 characters."))
    Ok(week), Ok(day), _ ->
      case string.length(description) > max_description {
        True ->
          Error(#("description", "The notes can have at most 5000 characters."))
        False ->
          case
            target_distance(form.distance_km),
            target_duration(form.duration),
            intervals(form),
            target_zone(form)
          {
            Error(message), _, _, _ -> Error(#("distance", message))
            _, Error(message), _, _ -> Error(#("duration", message))
            _, _, Error(problem), _ -> Error(problem)
            _, _, _, Error(message) -> Error(#("zone", message))
            Ok(distance), Ok(duration), Ok(intervals), Ok(zone) ->
              Ok(Valid(
                day_index: { week - 1 } * 7 + { day - 1 },
                title: title,
                kind: form.kind,
                distance_m: distance,
                duration_s: duration,
                description: description,
                intervals: intervals,
                zone: zone,
              ))
          }
      }
  }
}

fn target_distance(text: String) -> Result(Float, String) {
  case string.trim(text) {
    "" -> Ok(0.0)
    typed ->
      case parse_decimal(typed) {
        Ok(km) if km <=. max_distance_km -> Ok(km *. 1000.0)
        Ok(_) -> Error("The distance can be at most 1000 km.")
        Error(Nil) ->
          Error("Enter the distance in kilometres, for example 8 or 8.5.")
      }
  }
}

fn target_duration(text: String) -> Result(Int, String) {
  case string.trim(text) {
    "" -> Ok(0)
    typed ->
      case parse_duration(typed) {
        Ok(seconds) if seconds <= max_duration_seconds -> Ok(seconds)
        Ok(_) -> Error("The duration can be at most 48 hours.")
        Error(Nil) ->
          Error(
            "Enter the duration in minutes (45) or as hours and minutes (1:30).",
          )
      }
  }
}

/// The target zone; a rest day has none, whatever was chosen before its kind was changed (ADR 0105).
fn target_zone(form: Form) -> Result(Int, String) {
  case form.kind, int.parse(string.trim(form.zone)) {
    plan.Rest, _ -> Ok(0)
    _, _ if form.zone == "" -> Ok(0)
    _, Ok(n) if n >= 1 && n <= 5 -> Ok(n)
    _, _ -> Error("Choose a zone from 1 to 5.")
  }
}

/// `Zone 2`, `""` for none.
pub fn zone_label(zone: Int) -> String {
  case zone {
    0 -> ""
    n -> "Zone " <> int.to_string(n)
  }
}

/// The repetitions, for an interval workout only: none when every field of them is empty, as before
/// they existed (ADR 0104).
fn intervals(form: Form) -> Result(Option(Intervals), #(String, String)) {
  let reps = string.trim(form.reps)
  let typed = [reps, form.rep_distance, form.rep_time, form.recovery]
  case form.kind, list.all(typed, fn(text) { string.trim(text) == "" }) {
    plan.Interval, False ->
      case
        int.parse(reps),
        rep_distance(form.rep_distance),
        rep_time(form.rep_time, "time of a rep"),
        rep_time(form.recovery, "recovery")
      {
        Error(_), _, _, _ if reps == "" ->
          Error(#("reps", "Enter how many repetitions."))
        Error(_), _, _, _ ->
          Error(#("reps", "Enter the repetitions as a whole number."))
        Ok(n), _, _, _ if n < 1 || n > max_reps ->
          Error(#("reps", "The repetitions must be between 1 and 100."))
        _, Error(message), _, _ -> Error(#("rep_distance", message))
        _, _, Error(message), _ -> Error(#("rep_time", message))
        _, _, _, Error(message) -> Error(#("recovery", message))
        _, Ok(0.0), Ok(0), _ ->
          Error(#("rep_distance", "Give each rep a distance, a time or both."))
        Ok(n), Ok(distance), Ok(time), Ok(recovery) ->
          Ok(Some(Intervals(n, distance, time, recovery)))
      }
    _, _ -> Ok(None)
  }
}

fn rep_distance(text: String) -> Result(Float, String) {
  case string.trim(text) {
    "" -> Ok(0.0)
    typed ->
      case parse_decimal(typed) {
        Ok(m) if m <=. max_rep_distance_m -> Ok(int.to_float(float.round(m)))
        Ok(_) -> Error("The distance of a rep can be at most 20000 m.")
        Error(Nil) -> Error("Enter the distance in metres, for example 400.")
      }
  }
}

fn rep_time(text: String, what: String) -> Result(Int, String) {
  case string.trim(text) {
    "" -> Ok(0)
    typed ->
      case parse_rep_time(typed) {
        Ok(seconds) if seconds <= max_rep_seconds -> Ok(seconds)
        Ok(_) -> Error("The " <> what <> " can be at most 60 minutes.")
        Error(Nil) ->
          Error(
            "Enter the "
            <> what
            <> " in seconds (90) or as minutes and seconds (1:30).",
          )
      }
  }
}

/// Seconds from `90` (seconds), `1:30` (minutes and seconds) or `1:00:00` (with hours): reps and
/// recoveries are short, so a plain number means seconds here, not minutes as in `parse_duration`.
pub fn parse_rep_time(text: String) -> Result(Int, Nil) {
  case list.try_map(string.split(string.trim(text), ":"), parse_part) {
    Ok([seconds]) -> Ok(seconds)
    Ok([minutes, seconds]) if seconds < 60 -> Ok(minutes * 60 + seconds)
    Ok([hours, minutes, seconds]) if minutes < 60 && seconds < 60 ->
      Ok(hours * 3600 + minutes * 60 + seconds)
    _ -> Error(Nil)
  }
}

/// A rep or recovery time as it is typed back into the form and shown: `0:45`, `3:00`, `1:00:00`.
pub fn format_rep_time(seconds: Int) -> String {
  case seconds >= 3600 {
    True -> format_duration(seconds)
    False -> int.to_string(seconds / 60) <> ":" <> pad2(seconds % 60)
  }
}

/// `6 × 400 m in 1:15, 1:30 recovery`.
pub fn intervals_summary(intervals: Intervals) -> String {
  let distance = case intervals.rep_distance_m {
    m if m >=. 1000.0 -> format_km(m) <> " km"
    m if m >. 0.0 -> int.to_string(float.round(m)) <> " m"
    _ -> ""
  }
  let rep = case distance, intervals.rep_s {
    "", s -> format_rep_time(s)
    _, 0 -> distance
    _, s -> distance <> " in " <> format_rep_time(s)
  }
  let recovery = case intervals.recovery_s {
    0 -> ""
    s -> ", " <> format_rep_time(s) <> " recovery"
  }
  int.to_string(intervals.reps) <> " × " <> rep <> recovery
}

/// A non-negative decimal number, with a point or a comma: `5`, `5.5`, `5,5`, `.5`.
pub fn parse_decimal(text: String) -> Result(Float, Nil) {
  let normal = string.replace(string.trim(text), ",", ".")
  let candidate = case string.starts_with(normal, ".") {
    True -> "0" <> normal
    False -> normal
  }
  case int.parse(candidate) {
    Ok(whole) if whole >= 0 -> Ok(int.to_float(whole))
    Ok(_) -> Error(Nil)
    Error(_) ->
      case string.ends_with(candidate, "."), float.parse(candidate) {
        True, _ -> parse_decimal(string.drop_end(candidate, 1))
        False, Ok(value) if value >=. 0.0 -> Ok(value)
        _, _ -> Error(Nil)
      }
  }
}

/// Seconds from `45` (minutes), `1:30` (hours and minutes) or `1:30:15` (with seconds).
pub fn parse_duration(text: String) -> Result(Int, Nil) {
  case list.try_map(string.split(string.trim(text), ":"), parse_part) {
    Ok([minutes]) -> Ok(minutes * 60)
    Ok([hours, minutes]) if minutes < 60 -> Ok(hours * 3600 + minutes * 60)
    Ok([hours, minutes, seconds]) if minutes < 60 && seconds < 60 ->
      Ok(hours * 3600 + minutes * 60 + seconds)
    _ -> Error(Nil)
  }
}

fn parse_part(part: String) -> Result(Int, Nil) {
  case int.parse(string.trim(part)) {
    Ok(n) if n >= 0 -> Ok(n)
    _ -> Error(Nil)
  }
}

/// A distance as it is typed back into the form: `8`, `8.5`, `10.234`.
pub fn format_km(meters: Float) -> String {
  let thousandths = float.round(meters)
  let whole = thousandths / 1000
  let rest = thousandths % 1000
  case rest {
    0 -> int.to_string(whole)
    _ -> {
      let digits =
        string.pad_start(int.to_string(rest), 3, "0")
        |> trim_trailing_zeros
      int.to_string(whole) <> "." <> digits
    }
  }
}

fn trim_trailing_zeros(text: String) -> String {
  case string.ends_with(text, "0") {
    True -> trim_trailing_zeros(string.drop_end(text, 1))
    False -> text
  }
}

/// A duration as it is typed back into the form: `45`, `1:30` or `1:30:15`.
pub fn format_duration(seconds: Int) -> String {
  let hours = seconds / 3600
  let minutes = { seconds % 3600 } / 60
  let rest = seconds % 60
  case hours, rest {
    0, 0 -> int.to_string(minutes)
    _, 0 -> int.to_string(hours) <> ":" <> pad2(minutes)
    _, _ -> int.to_string(hours) <> ":" <> pad2(minutes) <> ":" <> pad2(rest)
  }
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}

// FIELDS TO WRITE ---------------------------------------------------------------------------------

/// The fields of a new workout. `position` orders it among the workouts of its day.
pub fn create_fields(
  plan_id: String,
  position: Int,
  valid: Valid,
) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("plan", plan_id),
    outbox.field_int("position", position),
    ..value_fields(valid)
  ])
}

/// Only what differs from the stored workout. When the day changes the workout moves to the end
/// of its new day (`new_position`). Empty when nothing changed.
pub fn changed_fields(
  row: Row,
  valid: Valid,
  new_position: Int,
) -> outbox.Fields {
  let w = row.workout
  let moved = valid.day_index != w.day_index
  let changed =
    value_fields(valid)
    |> list.filter(fn(field) {
      case field.0 {
        "day_index" -> moved
        "title" -> valid.title != w.title
        "kind" -> valid.kind != w.kind
        "description" -> valid.description != row.description
        "distance_m" -> valid.distance_m != option.unwrap(w.distance_m, 0.0)
        "duration_s" -> valid.duration_s != option.unwrap(w.duration_s, 0)
        "steps" -> valid.intervals != row.intervals
        "zone" -> valid.zone != row.zone
        _ -> False
      }
    })
  let with_position = case moved {
    True -> [outbox.field_int("position", new_position), ..changed]
    False -> changed
  }
  dict.from_list(with_position)
}

fn value_fields(valid: Valid) -> List(#(String, String)) {
  [
    outbox.field_int("day_index", valid.day_index),
    outbox.field_string("title", valid.title),
    outbox.field_string("kind", plan.kind_to_string(valid.kind)),
    outbox.field_string("description", valid.description),
    outbox.field_float("distance_m", valid.distance_m),
    outbox.field_int("duration_s", valid.duration_s),
    steps_field(valid.intervals),
    outbox.field_int("zone", valid.zone),
  ]
}

/// The repetitions as the `steps` JSON (ADR 0104), `null` when there are none. Unset values are left out.
pub fn steps_field(intervals: Option(Intervals)) -> #(String, String) {
  case intervals {
    None -> outbox.field_null("steps")
    Some(i) -> {
      let work =
        [
          #("distance_m", i.rep_distance_m >. 0.0, json.float(i.rep_distance_m)),
          #("duration_s", i.rep_s > 0, json.int(i.rep_s)),
        ]
        |> list.filter(fn(part) { part.1 })
        |> list.map(fn(part) { #(part.0, part.2) })
      let recovery = case i.recovery_s {
        0 -> []
        s -> [#("recovery", json.object([#("duration_s", json.int(s))]))]
      }
      #(
        "steps",
        json.object([
          #("v", json.int(1)),
          #("reps", json.int(i.reps)),
          #("work", json.object(work)),
          ..recovery
        ])
          |> json.to_string,
      )
    }
  }
}

pub fn kind_label(kind: Kind) -> String {
  case kind {
    plan.Easy -> "Easy run"
    plan.Long -> "Long run"
    plan.Tempo -> "Tempo run"
    plan.Interval -> "Intervals"
    plan.Race -> "Race"
    plan.Rest -> "Rest day"
    plan.Cross -> "Cross-training"
    plan.Strength -> "Strength"
  }
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
