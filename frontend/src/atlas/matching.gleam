//// Matching recorded activities to planned workouts. Pure, deterministic and conservative:
//// an activity matches a workout only on the same local day, with a compatible sport and a size
//// that is not wildly off. Each activity and each scheduled workout is used at most once.

import atlas/activity.{type Activity}
import atlas/date.{type Date}
import atlas/plan.{type Scheduled}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/set
import gleam/string

pub type Match {
  Match(activity_id: String, workout_id: String, assignment_id: String)
}

/// A match as stored (ADR 0009): the user's confirmation or choice, kept apart from live proposals.
/// Removed matches stay as rows (`deleted`) because an activity has at most one match row.
pub type Stored {
  Stored(
    id: String,
    owner_id: String,
    match: Match,
    deleted: Bool,
    /// The `updated` value of the local copy: the base for edits (ADR 0011).
    updated: String,
  )
}

pub type Status {
  /// Matched with the activity of this ID.
  Done(activity_id: String)
  /// In the future or today, not done yet.
  Planned
  /// In the past with no matching activity.
  Missed
  /// A rest day: nothing to do.
  RestDay
}

/// How far an activity may differ from the planned distance (or duration), as a share of the plan.
/// 0.5 accepts anything from half to one and a half times the planned size.
const max_relative_difference = 0.5

/// Proposes new matches for the scheduled workouts. `existing` matches (made earlier or confirmed
/// by the user) are kept out of the proposal: their activities and workouts are not used again.
/// `offset_at` gives the athlete's UTC offset in minutes at a UTC timestamp. It is a function, not a number,
/// because the offset changes with daylight saving and decides on which local day an activity happened.
pub fn propose(
  scheduled: List(Scheduled),
  activities: List(Activity),
  existing: List(Match),
  offset_at: fn(String) -> Int,
) -> List(Match) {
  let used_activities =
    set.from_list(list.map(existing, fn(m) { m.activity_id }))
  let used_workouts =
    set.from_list(
      list.map(existing, fn(m) { key(m.assignment_id, m.workout_id) }),
    )

  let candidates =
    list.flat_map(scheduled, fn(s) {
      case
        s.workout.kind == plan.Rest
        || set.contains(used_workouts, key(s.assignment_id, s.workout.id))
      {
        True -> []
        False ->
          activities
          |> list.filter(fn(a) { !set.contains(used_activities, a.id) })
          |> list.filter_map(fn(a) { candidate(s, a, offset_at) })
      }
    })

  candidates
  |> list.sort(fn(a, b) {
    float.compare(a.score, b.score)
    |> order.lazy_break_tie(fn() {
      string.compare(a.match.workout_id, b.match.workout_id)
    })
    |> order.lazy_break_tie(fn() {
      string.compare(a.match.assignment_id, b.match.assignment_id)
    })
    |> order.lazy_break_tie(fn() {
      string.compare(a.match.activity_id, b.match.activity_id)
    })
  })
  |> pick_best(set.new(), set.new(), [])
  |> list.sort(fn(a, b) {
    string.compare(a.workout_id, b.workout_id)
    |> order.lazy_break_tie(fn() {
      string.compare(a.assignment_id, b.assignment_id)
    })
  })
}

/// Whether a scheduled workout is done, still to do or missed, given the matches and today's date.
pub fn status(
  scheduled: Scheduled,
  matches: List(Match),
  today: Date,
) -> Status {
  case scheduled.workout.kind == plan.Rest {
    True -> RestDay
    False ->
      case
        list.find(matches, fn(m) {
          m.workout_id == scheduled.workout.id
          && m.assignment_id == scheduled.assignment_id
        })
      {
        Ok(m) -> Done(m.activity_id)
        Error(Nil) ->
          case date.compare(scheduled.date, today) {
            order.Lt -> Missed
            _ -> Planned
          }
      }
  }
}

type Candidate {
  Candidate(match: Match, score: Float)
}

fn candidate(
  scheduled: Scheduled,
  activity: Activity,
  offset_at: fn(String) -> Int,
) -> Result(Candidate, Nil) {
  case
    date.local_date(activity.started_at, offset_at(activity.started_at)),
    compatible(scheduled.workout.kind, activity.sport)
  {
    Ok(day), True if day == scheduled.date ->
      case score(scheduled, activity) {
        Ok(score) ->
          Ok(Candidate(
            Match(activity.id, scheduled.workout.id, scheduled.assignment_id),
            score,
          ))
        Error(Nil) -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
}

/// Which sports can fulfil which kind of workout.
pub fn compatible(kind: plan.Kind, sport: activity.Sport) -> Bool {
  case kind {
    plan.Easy | plan.Long | plan.Tempo | plan.Interval | plan.Race ->
      sport == activity.Run || sport == activity.TrailRun
    plan.Cross ->
      list.contains(
        [
          activity.Ride,
          activity.Swim,
          activity.Hike,
          activity.Walk,
          activity.Other,
        ],
        sport,
      )
    plan.Strength -> sport == activity.Strength
    plan.Rest -> False
  }
}

/// Lower is better: the relative difference to the planned distance, else to the planned duration.
/// A workout without targets scores a neutral 0.5. `Error` when the activity is too far off.
fn score(scheduled: Scheduled, activity: Activity) -> Result(Float, Nil) {
  let workout = scheduled.workout
  let difference = case workout.distance_m, workout.duration_s {
    Some(target), _ if target >. 0.0 ->
      Some(float.absolute_value(activity.distance_m -. target) /. target)
    _, Some(target) if target > 0 -> {
      let t = int.to_float(target)
      Some(float.absolute_value(int.to_float(activity.moving_time_s) -. t) /. t)
    }
    _, _ -> None
  }
  case difference {
    None -> Ok(0.5)
    Some(d) if d <=. max_relative_difference -> Ok(d)
    Some(_) -> Error(Nil)
  }
}

fn pick_best(
  sorted: List(Candidate),
  used_activities: set.Set(String),
  used_workouts: set.Set(String),
  picked: List(Match),
) -> List(Match) {
  case sorted {
    [] -> picked
    [Candidate(m, _), ..rest] -> {
      let workout_key = key(m.assignment_id, m.workout_id)
      case
        set.contains(used_activities, m.activity_id)
        || set.contains(used_workouts, workout_key)
      {
        True -> pick_best(rest, used_activities, used_workouts, picked)
        False ->
          pick_best(
            rest,
            set.insert(used_activities, m.activity_id),
            set.insert(used_workouts, workout_key),
            [m, ..picked],
          )
      }
    }
  }
}

fn key(assignment_id: String, workout_id: String) -> String {
  assignment_id <> "/" <> workout_id
}
