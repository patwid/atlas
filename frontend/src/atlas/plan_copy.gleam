//// Copying a plan, with its workouts, into the user's own plans (ADR 0028). Pure: it only decides which
//// records to create. The copy is private, remembers what it was copied from, and starts with the same
//// workouts on the same days, and the same phases, goal and week intensities (ADR 0043). It has no
//// assignments: whoever copies it decides when to start it.

import atlas/outbox
import atlas/plan.{type Plan}
import atlas/plan_form
import atlas/workout_form.{type Row}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/string

pub const prefix = "Copy of "

/// Everything a copy consists of. The plan has to reach the server before its workouts do; creating the
/// plan first and the workouts after it (in this order) guarantees that (ADR 0016).
pub type Copy {
  Copy(
    plan_id: String,
    plan_fields: outbox.Fields,
    workouts: List(#(String, outbox.Fields)),
  )
}

/// `new_id` supplies a fresh record ID each time it is called.
pub fn build(
  source: Plan,
  workouts: List(Row),
  owner_id: String,
  new_id: fn() -> String,
) -> Copy {
  let plan_id = new_id()
  Copy(
    plan_id: plan_id,
    plan_fields: dict.from_list([
      outbox.field_string("owner", owner_id),
      outbox.field_string("title", title(source.title)),
      outbox.field_string("description", source.description),
      outbox.field_string("visibility", "private"),
      outbox.field_string("source_plan", source.id),
      outbox.field_int("base_weeks", source.phases.base_weeks),
      outbox.field_int(
        "pre_competition_weeks",
        source.phases.pre_competition_weeks,
      ),
      outbox.field_int("competition_weeks", source.phases.competition_weeks),
      outbox.field_float(
        "weekly_distance_m",
        option_float(source.weekly_distance_m),
      ),
      #("week_intensity", plan_form.encode_intensities(source.week_intensity)),
    ]),
    workouts: workouts
      |> list.sort(fn(a, b) {
        case a.workout.day_index == b.workout.day_index {
          True -> position_then_id(a, b)
          False -> int.compare(a.workout.day_index, b.workout.day_index)
        }
      })
      |> list.map(fn(row) { #(new_id(), workout_fields(plan_id, row)) }),
  )
}

/// `Copy of 10k plan`, cut short so that it still fits the server's limit for titles.
pub fn title(original: String) -> String {
  let wanted = prefix <> original
  case string.length(wanted) > plan_form.max_title {
    True -> string.slice(wanted, 0, plan_form.max_title)
    False -> wanted
  }
}

fn workout_fields(plan_id: String, row: Row) -> outbox.Fields {
  let w = row.workout
  dict.from_list([
    outbox.field_string("plan", plan_id),
    outbox.field_int("day_index", w.day_index),
    outbox.field_int("position", w.position),
    outbox.field_string("title", w.title),
    outbox.field_string("kind", plan.kind_to_string(w.kind)),
    outbox.field_string("description", row.description),
    outbox.field_float("distance_m", option_float(w.distance_m)),
    outbox.field_int("duration_s", option_int(w.duration_s)),
  ])
}

fn option_float(value: option.Option(Float)) -> Float {
  option.unwrap(value, 0.0)
}

fn option_int(value: option.Option(Int)) -> Int {
  option.unwrap(value, 0)
}

fn position_then_id(a: Row, b: Row) -> order.Order {
  case int.compare(a.workout.position, b.workout.position) {
    order.Eq -> string.compare(a.workout.id, b.workout.id)
    other -> other
  }
}
