//// The layout of a plan as weeks and days, for showing and editing it. Day 1 is the plan's first day;
//// which weekday that is depends on the start date of an assignment (ADR 0009), so the plan itself
//// only has "Week 3, day 2".

import atlas/plan.{type Workout}
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/string

pub type Day {
  /// `number` is 1-7 within the week, `index` the plan's 0-based day.
  Day(number: Int, index: Int, workouts: List(Workout))
}

pub type Week {
  Week(number: Int, days: List(Day), distance_m: Float, duration_s: Int)
}

/// All weeks from the first to the last that holds a workout, with empty days included so that
/// every day can be a place to add one. A plan without workouts has no weeks.
pub fn weeks(workouts: List(Workout)) -> List(Week) {
  case plan.length_days(workouts) {
    0 -> []
    length -> {
      let week_count = { length + 6 } / 7
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
        )
      })
    }
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
