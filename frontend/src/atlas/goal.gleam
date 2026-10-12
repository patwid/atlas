//// An athlete's race goals (ADR 0115): any number of them, each a distance and the time to run it in. Pure: the
//// form, its checks, the fields to write and how a goal reads.

import atlas/outbox
import atlas/units
import atlas/workout_form
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/order

/// The longest distance and time a goal can have, as for an activity.
const max_distance_m = 1_000_000.0

const max_time_s = 172_800

pub type Goal {
  Goal(
    id: String,
    owner_id: String,
    distance_m: Float,
    time_s: Int,
    updated: String,
  )
}

/// The goals of `me`, shortest distance first. Coaches' devices also hold their athletes' goals.
pub fn of(goals: List(Goal), me: String) -> List(Goal) {
  goals
  |> list.filter(fn(goal) { goal.owner_id == me })
  |> list.sort(fn(a, b) {
    case float.compare(a.distance_m, b.distance_m) {
      order.Eq -> int.compare(a.time_s, b.time_s)
      other -> other
    }
  })
}

/// The text of the form: the distance in kilometres and the time.
pub type Form {
  Form(distance_km: String, time: String)
}

pub fn empty_form() -> Form {
  Form("", "")
}

pub fn to_form(goal: Goal) -> Form {
  Form(
    workout_form.format_km(goal.distance_m),
    workout_form.format_duration(goal.time_s),
  )
}

/// The distance in metres and the time in seconds, both required, or the field that is wrong (`distance` or
/// `time`) and what is wrong with it.
pub fn parse(form: Form) -> Result(#(Float, Int), #(String, String)) {
  case workout_form.parse_decimal(form.distance_km) {
    Ok(km) if km >. 0.0 && km *. 1000.0 <=. max_distance_m ->
      case workout_form.parse_duration(form.time) {
        Ok(seconds) if seconds > 0 && seconds <= max_time_s ->
          Ok(#(km *. 1000.0, seconds))
        Ok(seconds) if seconds > 0 ->
          Error(#("time", "The time can be at most 48 hours."))
        _ ->
          Error(#(
            "time",
            "Enter the time as hours, minutes and seconds (0:45:30), hours and minutes (3:30) or minutes (45).",
          ))
      }
    Ok(km) if km >. 0.0 ->
      Error(#("distance", "The distance can be at most 1000 km."))
    _ ->
      Error(#(
        "distance",
        "Enter the distance in kilometres, for example 10 or 21.1.",
      ))
  }
}

/// The fields to write: the owner and both values, so the stored row is always complete.
pub fn fields(owner: String, distance_m: Float, time_s: Int) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("owner", owner),
    outbox.field_float("distance_m", distance_m),
    outbox.field_int("time_s", time_s),
  ])
}

/// `10 km`, `42.195 km`
pub fn distance(goal: Goal) -> String {
  workout_form.format_km(goal.distance_m) <> " km"
}

/// `45:00 · 4:30 /km`: the time as a race time, and the pace it takes.
pub fn time_and_pace(goal: Goal) -> String {
  let time = units.format_duration(goal.time_s)
  case units.pace_seconds_per_km(goal.distance_m, goal.time_s) {
    Ok(pace) -> time <> " · " <> units.format_pace(pace)
    Error(Nil) -> time
  }
}

/// `10 km in 45:00`
pub fn summary(goal: Goal) -> String {
  distance(goal) <> " in " <> units.format_duration(goal.time_s)
}
