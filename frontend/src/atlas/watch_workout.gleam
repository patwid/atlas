//// A workout as a watch runs it (ADR 0122): a flat list of steps, each ending on a distance, a time or a lap press,
//// at a pace range or without a target, and steps that repeat the ones before them. Pure.

import atlas/pace_zones.{type PaceZones}
import atlas/plan.{type Segment, type Set}
import atlas/workout_form.{type Row}
import gleam/int
import gleam/list
import gleam/option.{None, Some}

pub type Intensity {
  Warmup
  Active
  Recovery
  Cooldown
}

pub type End {
  Distance(metres: Float)
  Time(seconds: Int)
  LapPress
}

pub type Target {
  Open
  /// Seconds per km: `slowest` is the larger number.
  Pace(slowest: Int, fastest: Int)
}

pub type Step {
  Step(intensity: Intensity, end: End, target: Target)
  /// Runs the steps from index `from` (from 0) up to this one again, until they have been run `times` times in all.
  Repeat(from: Int, times: Int)
}

/// How far from a race goal's pace a rep may be, in seconds per km.
const goal_margin_s = 5

/// Every kind but a rest day can be run on a watch.
pub fn can_export(kind: plan.Kind) -> Bool {
  kind != plan.Rest
}

/// The steps of a workout as last saved, with targets from the pace zones of the athlete who runs it. `[]` for a
/// rest day.
pub fn steps(row: Row, zones: PaceZones) -> List(Step) {
  let w = row.workout
  let parts =
    option.unwrap(
      row.intervals,
      plan.Intervals(plan.no_segment, [], plan.no_segment),
    )
  let warmup = part(parts.warmup, Warmup, zones)
  let cooldown = part(parts.cooldown, Cooldown, zones)
  let main =
    Step(
      Active,
      end(
        option.unwrap(w.distance_m, 0.0),
        option.unwrap(w.duration_s, 0),
        True,
      )
        |> option.unwrap(LapPress),
      zone_target(row.zone, zones),
    )
  case w.kind {
    plan.Rest -> []
    plan.Run -> [main]
    plan.Race -> list.flatten([warmup, [main], cooldown])
    plan.Interval -> {
      let sets = sets(parts.sets, list.length(warmup), zones)
      list.flatten([warmup, sets, cooldown])
    }
  }
}

/// A warm-up, cool-down or recovery: run by the clock, or `[]` when it has neither a time nor a distance.
fn part(
  segment: Segment,
  intensity: Intensity,
  zones: PaceZones,
) -> List(Step) {
  case end(segment.distance_m, segment.duration_s, False) {
    Some(e) -> [Step(intensity, e, target(segment, zones))]
    None -> []
  }
}

/// The sets from step index `start` on. A recovery follows every rep but the last of the workout (ADR 0116).
fn sets(sets: List(Set), start: Int, zones: PaceZones) -> List(Step) {
  let runnable =
    list.filter_map(sets, fn(set) {
      case set.reps >= 1, end(set.work.distance_m, set.work.duration_s, True) {
        True, Some(e) -> Ok(#(set, Step(Active, e, target(set.work, zones))))
        _, _ -> Error(Nil)
      }
    })
  let last = list.length(runnable) - 1
  let #(steps, _) =
    list.index_fold(runnable, #([], start), fn(acc, pair, index) {
      let #(done, from) = acc
      let #(set, work) = pair
      let recovery = part(set.recovery, Recovery, zones)
      let these = case recovery, index == last {
        [], _ -> [work, ..repeat(from, set.reps)]
        _, False -> list.flatten([[work], recovery, repeat(from, set.reps)])
        _, True if set.reps == 1 -> [work]
        _, True ->
          list.flatten([[work], recovery, repeat(from, set.reps - 1), [work]])
      }
      #(list.append(done, these), from + list.length(these))
    })
  steps
}

/// A step that repeats those from `from`, or none when they are run only once.
fn repeat(from: Int, times: Int) -> List(Step) {
  case times > 1 {
    True -> [Repeat(from, times)]
    False -> []
  }
}

/// How a part ends: its distance or its time, whichever is preferred and set, else the other.
fn end(
  distance_m: Float,
  duration_s: Int,
  distance_first: Bool,
) -> option.Option(End) {
  case distance_first, distance_m >. 0.0, duration_s > 0 {
    True, True, _ | False, True, False -> Some(Distance(distance_m))
    _, _, True -> Some(Time(duration_s))
    _, False, False -> None
  }
}

fn target(segment: Segment, zones: PaceZones) -> Target {
  case segment.goal {
    Some(goal) ->
      case
        workout_form.goal_pace(
          workout_form.RaceGoal(goal.goal_id, goal.distance_m, goal.time_s),
          goal.intensity,
        )
      {
        Ok(pace) ->
          Pace(
            pace + goal_margin_s,
            int.max(pace - goal_margin_s, pace_zones.fastest_s),
          )
        Error(Nil) -> Open
      }
    None -> zone_target(segment.zone, zones)
  }
}

/// A zone's pace range. Zone 5 has no faster end, so it runs to the fastest pace there is.
fn zone_target(zone: Int, zones: PaceZones) -> Target {
  case list.find(pace_zones.zones(zones), fn(z) { z.number == zone }) {
    Ok(z) -> Pace(z.slowest, option.unwrap(z.fastest, pace_zones.fastest_s))
    Error(Nil) -> Open
  }
}
