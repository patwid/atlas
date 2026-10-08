//// The layout of a plan as weeks and days, for showing and editing it. Day 1 is the plan's first day;
//// which weekday that is depends on the start date of an assignment (ADR 0009), so the plan itself
//// only has "Week 3, day 2". Weeks belong to the plan's phases in order (ADR 0043).

import atlas/plan.{type Phase, type Phases, type Workout}
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string

pub type Day {
  /// `number` is 1-7 within the week, `index` the plan's 0-based day.
  Day(number: Int, index: Int, workouts: List(Workout))
}

pub type Week {
  Week(
    number: Int,
    days: List(Day),
    distance_m: Float,
    duration_s: Int,
    /// The week's phase and its number within it; an error after the last phase week.
    phase: Result(#(Phase, Int), Nil),
  )
}

/// Consecutive weeks of one phase. `phase` is an error for the weeks after the phases (or of a plan
/// without phases).
pub type Band {
  Band(phase: Result(Phase, Nil), weeks: List(Week))
}

/// All weeks of the phases, and after them every week up to the last that holds a workout, with empty
/// days included so that every day can be a place to add one. A plan without phases or workouts has no weeks.
pub fn weeks(phases: Phases, workouts: List(Workout)) -> List(Week) {
  let with_workouts = { plan.length_days(workouts) + 6 } / 7
  case int.max(plan.phase_weeks(phases), with_workouts) {
    0 -> []
    week_count -> {
      one_to(week_count)
      |> list.map(fn(number) {
        let days =
          one_to(7)
          |> list.map(fn(day_number) {
            let index = { number - 1 } * 7 + { day_number - 1 }
            Day(
              day_number,
              index,
              workouts
                |> list.filter(fn(w) { w.day_index == index })
                |> list.sort(by_position),
            )
          })
        let in_week = list.flat_map(days, fn(day) { day.workouts })
        Week(
          number: number,
          days: days,
          distance_m: list.fold(in_week, 0.0, fn(total, w) {
            total +. option.unwrap(w.distance_m, 0.0)
          }),
          duration_s: list.fold(in_week, 0, fn(total, w) {
            total + option.unwrap(w.duration_s, 0)
          }),
          phase: plan.phase_of_week(phases, number),
        )
      })
    }
  }
}

/// The weeks grouped by phase, in order.
pub fn bands(weeks: List(Week)) -> List(Band) {
  weeks
  |> list.chunk(fn(week) { result.map(week.phase, fn(p) { p.0 }) })
  |> list.map(fn(chunk) {
    case chunk {
      [first, ..] -> Band(result.map(first.phase, fn(p) { p.0 }), chunk)
      [] -> Band(Error(Nil), [])
    }
  })
}

/// "Base, week 2" or, after the phases, "Week 14".
pub fn week_label(phases: Phases, number: Int) -> String {
  case plan.phase_of_week(phases, number) {
    Ok(#(phase, in_phase)) ->
      plan.phase_label(phase) <> ", week " <> int.to_string(in_phase)
    Error(Nil) -> "Week " <> int.to_string(number)
  }
}

/// The planned distance of a week against the plan's goal, from 0 (none) up; above 1.0 when over it.
/// An error when the plan has no goal.
pub fn goal_share(
  week: Week,
  goal_m: option.Option(Float),
) -> Result(Float, Nil) {
  case goal_m {
    option.Some(goal) if goal >. 0.0 -> Ok(week.distance_m /. goal)
    _ -> Error(Nil)
  }
}

/// The position for a workout added at the end of a day.
pub fn next_position(workouts: List(Workout), day_index: Int) -> Int {
  workouts
  |> list.filter(fn(w) { w.day_index == day_index })
  |> list.fold(0, fn(highest, w) { int.max(highest, w.position + 1) })
}

/// 1, 2, ... n.
fn one_to(n: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, n), fn(_, index) { index + 1 })
}

fn by_position(a: Workout, b: Workout) -> order.Order {
  order.lazy_break_tie(int.compare(a.position, b.position), fn() {
    string.compare(a.id, b.id)
  })
}
