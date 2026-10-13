//// The layout of a plan as weeks and days, for showing and editing it. Weeks run from Monday to Sunday, and week 1
//// is the week of the plan's start date; with a start date every day has its date (ADR 0108). Weeks are counted from
//// 1, with or without a start date (ADR 0126). Weeks belong to the plan's phases in order (ADR 0043).

import atlas/date.{type Date}
import atlas/plan.{type Phase, type Phases, type Workout}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

pub type Day {
  /// `number` is 1 (Monday) to 7 (Sunday), `index` the plan's 0-based day. `date` is None for a plan without a
  /// start date. `before_start`: a day of week 1 before the plan starts, shown but not part of the plan (ADR 0108).
  Day(
    number: Int,
    index: Int,
    date: Option(Date),
    before_start: Bool,
    workouts: List(Workout),
  )
}

pub type Week {
  Week(
    number: Int,
    /// "Week 3": what the calendar calls it (see `week_name`).
    name: String,
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
pub fn weeks(
  phases: Phases,
  start: Option(Date),
  workouts: List(Workout),
) -> List(Week) {
  let first_day = case start {
    Some(day) -> plan.first_day(day)
    None -> 0
  }
  case plan.week_count(phases, workouts) {
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
              option.map(start, plan.day_date(_, index)),
              index < first_day,
              workouts
                |> list.filter(fn(w) { w.day_index == index })
                |> list.sort(by_position),
            )
          })
        let in_week = list.flat_map(days, fn(day) { day.workouts })
        Week(
          number: number,
          name: week_name(number),
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

/// "16–22 Nov", "30 Nov – 6 Dec" or "28 Dec 2026 – 3 Jan 2027": the days of a week (Monday to Sunday) of a plan that
/// has a start date.
pub fn week_dates(week: Week) -> Result(String, Nil) {
  let day_month = fn(day: Date) {
    int.to_string(day.day) <> " " <> date.month_short(day.month)
  }
  case list.first(week.days), list.last(week.days) {
    Ok(Day(date: Some(first), ..)), Ok(Day(date: Some(last), ..)) ->
      Ok(case first.year == last.year, first.month == last.month {
        True, True -> int.to_string(first.day) <> "–" <> day_month(last)
        True, False -> day_month(first) <> " – " <> day_month(last)
        False, _ ->
          day_month(first)
          <> " "
          <> int.to_string(first.year)
          <> " – "
          <> day_month(last)
          <> " "
          <> int.to_string(last.year)
      })
    _, _ -> Error(Nil)
  }
}

/// "Mon" or, with a date, "Mon 16 Nov": a day's name in the calendar and in the workout form.
pub fn day_name(day: Day) -> String {
  let weekday = weekday_name(day.number)
  case day.date {
    Some(on) ->
      weekday
      <> " "
      <> int.to_string(on.day)
      <> " "
      <> date.month_short(on.month)
    None -> weekday
  }
}

/// "Mon" for 1 to "Sun" for 7.
pub fn weekday_name(number: Int) -> String {
  case number {
    1 -> "Mon"
    2 -> "Tue"
    3 -> "Wed"
    4 -> "Thu"
    5 -> "Fri"
    6 -> "Sat"
    _ -> "Sun"
  }
}

/// "Week 3" for the plan's week `number` (from 1), with or without a start date (ADR 0126).
pub fn week_name(number: Int) -> String {
  "Week " <> int.to_string(number)
}

/// "Week 6 · Pre-competition 2" or, outside the phases, "Week 13". It starts with the name the calendar's rows show,
/// so a week reads the same in a form or dialog as in the calendar.
pub fn week_label(phases: Phases, number: Int) -> String {
  let week = week_name(number)
  case plan.phase_of_week(phases, number) {
    Ok(#(phase, in_phase)) ->
      week <> " · " <> plan.phase_label(phase) <> " " <> int.to_string(in_phase)
    Error(Nil) -> week
  }
}

/// A week's distance goal (ADR 0064): the plan's weekly goal scaled by the week's intensity, so an easy week at 60%
/// aims for 60% of it; the full goal when the week has no intensity, and none when the plan has no goal.
pub fn week_goal(
  goal_m: option.Option(Float),
  intensity: Result(Float, Nil),
) -> option.Option(Float) {
  case goal_m, intensity {
    option.Some(goal), Ok(level) -> option.Some(goal *. level)
    option.Some(goal), Error(Nil) -> option.Some(goal)
    option.None, _ -> option.None
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
