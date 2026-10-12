//// Training plans: a workout sits on a day of the plan, counted from the Monday of the week the plan starts in, and
//// the plan's start date puts those days on the calendar. An assignment follows the plan's date or has its own
//// (ADR 0009, 0108). Pure functions only.

import atlas/date.{type Date}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/string

pub type Kind {
  Run
  Interval
  Race
  Rest
}

pub type Plan {
  Plan(
    id: String,
    owner_id: String,
    title: String,
    description: String,
    /// The `updated` value of the local copy: the base for edits (ADR 0011). Empty until first synced.
    updated: String,
    phases: Phases,
    weekly_distance_m: Option(Float),
    /// By week number, from 1: 0.0 (easiest) to 1.0 (hardest). Weeks without an entry have no intensity set.
    week_intensity: Dict(Int, Float),
    /// The plan's first day (ADR 0108). None for a plan made before plans had one.
    start_date: Option(Date),
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

/// The parts of an interval workout, kept in its `steps` (ADR 0104, 0116): a warm-up, sets of repetitions and a
/// cool-down.
pub type Intervals {
  Intervals(warmup: Segment, sets: List(Set), cooldown: Segment)
}

/// `reps` times `work`, each followed by `recovery` except the last rep of the workout (ADR 0116).
pub type Set {
  Set(reps: Int, work: Segment, recovery: Segment)
}

/// A distance, a time or both, at a target zone from 1 to 5. 0 means not set. A rep can instead be run at an
/// intensity of one of the athlete's race goals (ADR 0118).
pub type Segment {
  Segment(zone: Int, distance_m: Float, duration_s: Int, goal: Option(GoalPace))
}

pub const no_segment = Segment(0, 0.0, 0, option.None)

/// A share of the speed of a race goal (ADR 0115, 0118): 100 is the goal's own pace. The goal's distance and time
/// are kept with it, so the pace can still be read when the goal is changed or gone, or not on the device.
pub type GoalPace {
  GoalPace(goal_id: String, distance_m: Float, time_s: Int, intensity: Int)
}

pub type Assignment {
  /// `start_date` None: the assignment follows its plan's start date (ADR 0108).
  Assignment(
    id: String,
    plan_id: String,
    athlete_id: String,
    start_date: Option(Date),
  )
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
  updated: String,
) -> Plan {
  Plan(
    id,
    owner_id,
    title,
    description,
    updated,
    Phases(0, 0, 0),
    option.None,
    dict.new(),
    option.None,
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

/// The kinds a workout had before there was one for every run are read as a run, as the server now stores them
/// (ADR 0114): a copy on the device keeps its old kind until the workout is next changed.
pub fn kind_from_string(text: String) -> Result(Kind, Nil) {
  case text {
    "run" | "easy" | "long" | "tempo" | "cross" | "strength" -> Ok(Run)
    "interval" -> Ok(Interval)
    "race" -> Ok(Race)
    "rest" -> Ok(Rest)
    _ -> Error(Nil)
  }
}

pub fn kind_to_string(kind: Kind) -> String {
  case kind {
    Run -> "run"
    Interval -> "interval"
    Race -> "race"
    Rest -> "rest"
  }
}

/// The first day of an assignment: its own start date, else its plan's (ADR 0108). An error when neither has one,
/// or the plan is not on the device.
pub fn start_of(
  assignment: Assignment,
  plans: List(Plan),
) -> Result(Date, Nil) {
  case assignment.start_date {
    option.Some(start) -> Ok(start)
    option.None ->
      case list.find(plans, fn(p) { p.id == assignment.plan_id }) {
        Ok(Plan(start_date: option.Some(start), ..)) -> Ok(start)
        _ -> Error(Nil)
      }
  }
}

/// Today if it is a Monday, else the next Monday: the first day a plan is offered (ADR 0108).
pub fn coming_monday(today: Date) -> Date {
  case date.start_of_week(today) == today {
    True -> today
    False -> date.add_days(date.start_of_week(today), 7)
  }
}

/// Day 0 of a plan that starts on `start`: the Monday of that week (ADR 0108).
pub fn first_monday(start: Date) -> Date {
  date.start_of_week(start)
}

/// The day index of the start date itself, 0 (Monday) to 6 (Sunday). The days before it are not part of the plan.
pub fn first_day(start: Date) -> Int {
  date.diff_days(from: first_monday(start), to: start)
}

/// The date of a day of a plan that starts on `start`.
pub fn day_date(start: Date, day_index: Int) -> Date {
  date.add_days(first_monday(start), day_index)
}

pub fn workout_date(start: Date, workout: Workout) -> Date {
  day_date(start, workout.day_index)
}

/// The workouts of the assignment's plan on their calendar days, from the assignment's first day `start` on, in
/// date, position and ID order. Workouts of other plans, and those before the start, are left out.
pub fn schedule(
  assignment: Assignment,
  start: Date,
  workouts: List(Workout),
) -> List(Scheduled) {
  workouts
  |> list.filter(fn(w) {
    w.plan_id == assignment.plan_id && w.day_index >= first_day(start)
  })
  |> list.map(fn(w) { Scheduled(assignment.id, workout_date(start, w), w) })
  |> list.sort(fn(a, b) {
    order.lazy_break_tie(date.compare(a.date, b.date), fn() {
      order.lazy_break_tie(
        int.compare(a.workout.position, b.workout.position),
        fn() { string.compare(a.workout.id, b.workout.id) },
      )
    })
  })
}

/// The number of days the plan's workouts span from day 0 (the last workout's day plus one); 0 for an empty plan.
pub fn length_days(workouts: List(Workout)) -> Int {
  list.fold(workouts, 0, fn(longest, w) {
    case w.day_index + 1 > longest {
      True -> w.day_index + 1
      False -> longest
    }
  })
}

/// The number of calendar weeks of a plan: its phase weeks, or up to the last week with a workout if that is later.
pub fn week_count(phases: Phases, workouts: List(Workout)) -> Int {
  int.max(phase_weeks(phases), { length_days(workouts) + 6 } / 7)
}

/// The last day of a plan that starts on `start`: the Sunday of its last week (ADR 0108). An error for a plan
/// without phases or workouts. Only the plan's own workouts are passed.
pub fn end_date(
  start: Date,
  phases: Phases,
  workouts: List(Workout),
) -> Result(Date, Nil) {
  case week_count(phases, workouts) {
    0 -> Error(Nil)
    weeks -> Ok(day_date(start, weeks * 7 - 1))
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
