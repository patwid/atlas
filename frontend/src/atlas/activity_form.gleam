//// Entering an activity by hand: parsing what the user typed (a local date and time, "8,5" km,
//// "45" minutes) and choosing the fields to write. Pure. A manual activity is stored with its start as a
//// UTC timestamp like all others, so the local date and time are converted with the UTC offset at that moment
//// (ADR 0025). Limits follow the server (ADR 0009).

import atlas/activity.{type Sport}
import atlas/date.{type Date}
import atlas/outbox
import atlas/workout_form
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

const max_name = 200

const max_elevation_m = 10_000

const min_heart_rate = 30

const max_heart_rate = 250

pub type Form {
  Form(
    /// `YYYY-MM-DD`, as a date picker gives it.
    date: String,
    /// `HH:MM`, as a time picker gives it.
    time: String,
    sport: Sport,
    name: String,
    distance_km: String,
    duration: String,
    elevation_m: String,
    avg_hr: String,
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
    name: String,
    distance_m: Float,
    duration_s: Int,
    elevation_m: Int,
    avg_hr: Int,
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
  )
}

pub fn empty_for(today: Date) -> Form {
  Form(date.to_string(today), "07:00", activity.Run, "", "", "", "", "", None)
}

/// The form for editing a stored activity. `offset` is the UTC offset in minutes at its start.
pub fn from_row(row: Row, offset: Int) -> Form {
  let #(day, hour, minute) = case
    date.local_datetime(row.activity.started_at, offset)
  {
    Ok(found) -> found
    Error(Nil) -> #(date.Date(1970, 1, 1), 0, 0)
  }
  Form(
    date: date.to_string(day),
    time: pad2(hour) <> ":" <> pad2(minute),
    sport: row.activity.sport,
    name: row.name,
    distance_km: case row.activity.distance_m >. 0.0 {
      True -> workout_form.format_km(row.activity.distance_m)
      False -> ""
    },
    duration: case row.activity.moving_time_s > 0 {
      True -> workout_form.format_duration(row.activity.moving_time_s)
      False -> ""
    },
    elevation_m: case row.elevation_m >. 0.0 {
      True -> int.to_string(float.round(row.elevation_m))
      False -> ""
    },
    avg_hr: case row.avg_hr > 0 {
      True -> int.to_string(row.avg_hr)
      False -> ""
    },
    error: None,
  )
}

/// Checks the form; a problem names the field it is about: `date`, `time`, `name`, `distance`, `duration`,
/// `elevation` or `avg_hr`.
pub fn validate_fields(form: Form) -> Result(Valid, #(String, String)) {
  let name = string.trim(form.name)
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
              Error(#("name", "The name can have at most 200 characters."))
            False ->
              case
                optional(form.distance_km, 0.0, distance),
                optional(form.duration, 0, duration),
                whole(form.elevation_m, "elevation", 0, max_elevation_m),
                whole(
                  form.avg_hr,
                  "average heart rate",
                  min_heart_rate,
                  max_heart_rate,
                )
              {
                Error(message), _, _, _ -> Error(#("distance", message))
                _, Error(message), _, _ -> Error(#("duration", message))
                _, _, Error(message), _ -> Error(#("elevation", message))
                _, _, _, Error(message) -> Error(#("avg_hr", message))
                Ok(distance_m), Ok(duration_s), Ok(elevation), Ok(heart_rate) ->
                  case distance_m <=. 0.0 && duration_s <= 0 {
                    True ->
                      Error(#(
                        "distance",
                        "Enter a distance or a time, or both.",
                      ))
                    False ->
                      Ok(Valid(
                        day: day,
                        hour: hour,
                        minute: minute,
                        sport: form.sport,
                        name: name,
                        distance_m: distance_m,
                        duration_s: duration_s,
                        elevation_m: elevation,
                        avg_hr: heart_rate,
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

fn distance(text: String) -> Result(Float, String) {
  case workout_form.parse_decimal(text) {
    Ok(km) if km <=. 1000.0 -> Ok(km *. 1000.0)
    Ok(_) -> Error("The distance can be at most 1000 km.")
    Error(Nil) ->
      Error("Enter the distance in kilometres, for example 8 or 8.5.")
  }
}

fn duration(text: String) -> Result(Int, String) {
  case workout_form.parse_duration(text) {
    Ok(seconds) if seconds <= 172_800 -> Ok(seconds)
    Ok(_) -> Error("The time can be at most 48 hours.")
    Error(Nil) ->
      Error("Enter the time in minutes (45) or as hours and minutes (1:30).")
  }
}

/// An optional field: empty gives `none_value`, anything else must parse.
fn optional(
  text: String,
  none_value: a,
  parse: fn(String) -> Result(a, String),
) -> Result(a, String) {
  case string.trim(text) {
    "" -> Ok(none_value)
    typed -> parse(typed)
  }
}

fn whole(
  text: String,
  what: String,
  low: Int,
  high: Int,
) -> Result(Int, String) {
  case string.trim(text) {
    "" -> Ok(0)
    typed ->
      case int.parse(typed) {
        Ok(n) if n >= low && n <= high -> Ok(n)
        _ ->
          Error(
            "The "
            <> what
            <> " must be a whole number from "
            <> int.to_string(low)
            <> " to "
            <> int.to_string(high)
            <> ".",
          )
      }
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
      "name" -> valid.name != row.name
      "distance_m" -> valid.distance_m != a.distance_m
      "moving_time_s" -> valid.duration_s != a.moving_time_s
      "elapsed_time_s" -> valid.duration_s != a.moving_time_s
      "elevation_gain_m" -> int.to_float(valid.elevation_m) != row.elevation_m
      "avg_hr" -> valid.avg_hr != row.avg_hr
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
    outbox.field_string("name", valid.name),
    outbox.field_float("distance_m", valid.distance_m),
    outbox.field_int("moving_time_s", valid.duration_s),
    outbox.field_int("elapsed_time_s", valid.duration_s),
    outbox.field_int("elevation_gain_m", valid.elevation_m),
    outbox.field_int("avg_hr", valid.avg_hr),
  ]
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
