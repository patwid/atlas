//// Training plans as templates: a workout sits on a day of the plan (day 0 is the first day), and an
//// assignment gives the plan a start date for one athlete (ADR 0009). Pure functions only.

import atlas/date.{type Date}
import gleam/dict.{type Dict}
import gleam/float
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
    /// The `updated` value of the local copy: the base for edits (ADR 0011). Empty until first synced.
    updated: String,
    phases: Phases,
    weekly_distance_m: Option(Float),
    /// By week number, from 1: 0.0 (easiest) to 1.0 (hardest). Weeks without an entry have no intensity set.
    week_intensity: Dict(Int, Float),
  )
}

/// The periods of a plan, in this order (ADR 0043).
pub type Phase {
  Base
  PreCompetition
  Competition
}

/// How many weeks each phase lasts. All 0 for a plan made before phases existed: it has no phases.
pub type Phases {
  Phases(base_weeks: Int, pre_competition_weeks: Int, competition_weeks: Int)
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

/// What a new plan starts with: 4 weeks per phase.
pub const default_phases = Phases(4, 4, 4)

/// A plan's own fields, without phases, goal or intensities: what plans made before ADR 0043 hold.
pub fn new(
  id: String,
  owner_id: String,
  title: String,
  description: String,
  visibility: Visibility,
  updated: String,
) -> Plan {
  Plan(
    id,
    owner_id,
    title,
    description,
    visibility,
    updated,
    Phases(0, 0, 0),
    option.None,
    dict.new(),
  )
}

/// The number of weeks the phases cover; 0 for a plan without phases.
pub fn phase_weeks(phases: Phases) -> Int {
  phases.base_weeks + phases.pre_competition_weeks + phases.competition_weeks
}

/// The phase a week (from 1) belongs to, and its number within that phase (from 1). An error for a week
/// after the last phase.
pub fn phase_of_week(phases: Phases, week: Int) -> Result(#(Phase, Int), Nil) {
  let pre_start = phases.base_weeks
  let competition_start = pre_start + phases.pre_competition_weeks
  case week {
    _ if week < 1 -> Error(Nil)
    _ if week <= pre_start -> Ok(#(Base, week))
    _ if week <= competition_start -> Ok(#(PreCompetition, week - pre_start))
    _ if week <= competition_start + phases.competition_weeks ->
      Ok(#(Competition, week - competition_start))
    _ -> Error(Nil)
  }
}

pub fn phase_label(phase: Phase) -> String {
  case phase {
    Base -> "Base"
    PreCompetition -> "Pre-competition"
    Competition -> "Competition"
  }
}

/// An intensity within 0.0 to 1.0, to whole percent.
pub fn intensity(value: Float) -> Float {
  int.to_float(float.round(float.clamp(value, 0.0, 1.0) *. 100.0)) /. 100.0
}

/// `70%`
pub fn intensity_percent(value: Float) -> String {
  int.to_string(float.round(value *. 100.0)) <> "%"
}

pub fn visibility_to_string(visibility: Visibility) -> String {
  case visibility {
    Private -> "private"
    Public -> "public"
  }
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
