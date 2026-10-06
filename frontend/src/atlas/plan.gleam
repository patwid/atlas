//// Training plans as templates: a workout sits on a day of the plan (day 0 is the first day), and an
//// assignment gives the plan a start date for one athlete (ADR 0009). Pure functions only.

import atlas/date.{type Date}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/string

pub type Kind {
  Easy
  Long
  Tempo
  Interval
  Race
  Rest
  Cross
  Strength
}

pub type Visibility {
  Private
  Public
}

pub type Plan {
  Plan(
    id: String,
    owner_id: String,
    title: String,
    description: String,
    visibility: Visibility,
  )
}

pub type Workout {
  Workout(
    id: String,
    plan_id: String,
    day_index: Int,
    position: Int,
    title: String,
    kind: Kind,
    distance_m: Option(Float),
    duration_s: Option(Int),
  )
}

pub type Assignment {
  Assignment(id: String, plan_id: String, athlete_id: String, start_date: Date)
}

/// A workout placed on a calendar day by an assignment.
pub type Scheduled {
  Scheduled(assignment_id: String, date: Date, workout: Workout)
}

pub type WeekTotal {
  WeekTotal(week_start: Date, workouts: Int, distance_m: Float, duration_s: Int)
}

pub fn kind_from_string(text: String) -> Result(Kind, Nil) {
  case text {
    "easy" -> Ok(Easy)
    "long" -> Ok(Long)
    "tempo" -> Ok(Tempo)
    "interval" -> Ok(Interval)
    "race" -> Ok(Race)
    "rest" -> Ok(Rest)
    "cross" -> Ok(Cross)
    "strength" -> Ok(Strength)
    _ -> Error(Nil)
  }
}

pub fn kind_to_string(kind: Kind) -> String {
  case kind {
    Easy -> "easy"
    Long -> "long"
    Tempo -> "tempo"
    Interval -> "interval"
    Race -> "race"
    Rest -> "rest"
    Cross -> "cross"
    Strength -> "strength"
  }
}

pub fn workout_date(assignment: Assignment, workout: Workout) -> Date {
  date.add_days(assignment.start_date, workout.day_index)
}

/// The workouts of the assignment's plan on their calendar days, in date, position and ID order.
/// Workouts of other plans are ignored.
pub fn schedule(
  assignment: Assignment,
  workouts: List(Workout),
) -> List(Scheduled) {
  workouts
  |> list.filter(fn(w) { w.plan_id == assignment.plan_id })
  |> list.map(fn(w) { Scheduled(assignment.id, workout_date(assignment, w), w) })
  |> list.sort(fn(a, b) {
    order.lazy_break_tie(date.compare(a.date, b.date), fn() {
      order.lazy_break_tie(
        int.compare(a.workout.position, b.workout.position),
        fn() { string.compare(a.workout.id, b.workout.id) },
      )
    })
  })
}

/// The number of days the plan spans (the last workout's day plus one); 0 for an empty plan.
pub fn length_days(workouts: List(Workout)) -> Int {
  list.fold(workouts, 0, fn(longest, w) {
    case w.day_index + 1 > longest {
      True -> w.day_index + 1
      False -> longest
    }
  })
}

/// The date of the last workout of an assignment.
pub fn end_date(
  assignment: Assignment,
  workouts: List(Workout),
) -> Result(Date, Nil) {
  case
    list.filter(workouts, fn(w) { w.plan_id == assignment.plan_id })
    |> length_days
  {
    0 -> Error(Nil)
    days -> Ok(date.add_days(assignment.start_date, days - 1))
  }
}

pub fn on_date(scheduled: List(Scheduled), day: Date) -> List(Scheduled) {
  list.filter(scheduled, fn(s) { s.date == day })
}

/// Planned load per week (weeks start on Monday), oldest first. Rest days are not counted as workouts.
pub fn weekly_totals(scheduled: List(Scheduled)) -> List(WeekTotal) {
  let by_week =
    list.fold(scheduled, dict.new(), fn(totals, s) {
      let week = date.start_of_week(s.date)
      let key = date.to_epoch_days(week)
      let current = case dict.get(totals, key) {
        Ok(total) -> total
        Error(Nil) -> WeekTotal(week, 0, 0.0, 0)
      }
      let counted = case s.workout.kind {
        Rest -> current
        _ -> WeekTotal(..current, workouts: current.workouts + 1)
      }
      dict.insert(
        totals,
        key,
        WeekTotal(
          ..counted,
          distance_m: counted.distance_m
            +. option.unwrap(s.workout.distance_m, 0.0),
          duration_s: counted.duration_s
            + option.unwrap(s.workout.duration_s, 0),
        ),
      )
    })
  dict.values(by_week)
  |> list.sort(fn(a, b) { date.compare(a.week_start, b.week_start) })
}
