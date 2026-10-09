//// The workout form: parsing what the user typed (a week, a day, "5,5" km, "1:30" hours) and choosing
//// which fields to write. Pure. Limits follow the server (ADR 0009).

import atlas/outbox
import atlas/plan.{type Kind, type Workout}
import gleam/dict
import gleam/float
import gleam/int
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
  )
}

/// A workout as stored, with the fields the domain type does not carry.
pub type Row {
  Row(workout: Workout, description: String, updated: String)
}

pub fn empty_for(week: Int, day: Int) -> Form {
  Form(int.to_string(week), int.to_string(day), "", plan.Easy, "", "", "", None)
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
    error: None,
  )
}

/// Checks the form; a problem names the field it is about: `week`, `day`, `title`, `description`, `distance` or
/// `duration`.
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
            target_duration(form.duration)
          {
            Error(message), _ -> Error(#("distance", message))
            _, Error(message) -> Error(#("duration", message))
            Ok(distance), Ok(duration) ->
              Ok(Valid(
                day_index: { week - 1 } * 7 + { day - 1 },
                title: title,
                kind: form.kind,
                distance_m: distance,
                duration_s: duration,
                description: description,
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
  ]
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
