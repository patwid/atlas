import atlas/activity.{type Activity, Activity}
import atlas/date.{Date}
import atlas/matching.{Done, Match, Missed, Planned, RestDay}
import atlas/plan.{type Scheduled, type Workout, Assignment, Workout}
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string

fn fixed(minutes: Int) -> fn(String) -> Int {
  fn(_) { minutes }
}

// Plan starts Monday 2026-10-05.
const start = Date(2026, 10, 5)

fn workout(
  id: String,
  day: Int,
  kind: plan.Kind,
  distance: option.Option(Float),
  duration: option.Option(Int),
) -> Workout {
  Workout(id, "p1", day, 0, id, kind, distance, duration)
}

fn schedule(workouts: List(Workout)) -> List(Scheduled) {
  plan.schedule(Assignment("a1", "p1", "alice", start), workouts)
}

fn run(
  id: String,
  timestamp: String,
  distance: Float,
  seconds: Int,
) -> Activity {
  Activity(id, activity.Fit, timestamp, activity.Run, distance, seconds)
}

pub fn matches_a_run_on_the_same_day_test() {
  let scheduled = schedule([workout("w1", 1, plan.Easy, Some(8000.0), None)])
  let acts = [run("act1", "2026-10-06 06:30:00.000Z", 8200.0, 2500)]
  assert matching.propose(scheduled, acts, [], fixed(0))
    == [Match("act1", "w1", "a1")]
}

pub fn the_day_is_the_local_day_test() {
  let scheduled = schedule([workout("w1", 1, plan.Easy, Some(8000.0), None)])
  // 22:30 UTC on the 5th is 00:30 on the 6th in UTC+2.
  let acts = [run("act1", "2026-10-05 22:30:00.000Z", 8000.0, 2500)]
  assert matching.propose(scheduled, acts, [], fixed(120))
    == [Match("act1", "w1", "a1")]
  assert matching.propose(scheduled, acts, [], fixed(0)) == []
}

pub fn other_days_do_not_match_test() {
  let scheduled = schedule([workout("w1", 1, plan.Easy, Some(8000.0), None)])
  let acts = [
    run("early", "2026-10-05 10:00:00.000Z", 8000.0, 2500),
    run("late", "2026-10-07 10:00:00.000Z", 8000.0, 2500),
  ]
  assert matching.propose(scheduled, acts, [], fixed(0)) == []
}

pub fn the_sport_must_fit_the_workout_test() {
  let scheduled = schedule([workout("w1", 1, plan.Easy, None, None)])
  let ride =
    Activity(
      "r",
      activity.Fit,
      "2026-10-06 10:00:00.000Z",
      activity.Ride,
      30_000.0,
      3600,
    )
  let trail =
    Activity(
      "t",
      activity.Fit,
      "2026-10-06 10:00:00.000Z",
      activity.TrailRun,
      8000.0,
      3000,
    )
  assert matching.propose(scheduled, [ride], [], fixed(0)) == []
  assert matching.propose(scheduled, [trail], [], fixed(0))
    == [Match("t", "w1", "a1")]
}

pub fn cross_training_and_strength_test() {
  assert matching.compatible(plan.Cross, activity.Ride)
  assert matching.compatible(plan.Cross, activity.Swim)
  assert !matching.compatible(plan.Cross, activity.Run)
  assert matching.compatible(plan.Strength, activity.Strength)
  assert !matching.compatible(plan.Strength, activity.Run)
  assert !matching.compatible(plan.Rest, activity.Run)
  assert !matching.compatible(plan.Rest, activity.Other)
}

pub fn rest_days_never_match_test() {
  let scheduled = schedule([workout("rest", 1, plan.Rest, None, None)])
  let acts = [run("act1", "2026-10-06 06:30:00.000Z", 5000.0, 1600)]
  assert matching.propose(scheduled, acts, [], fixed(0)) == []
}

pub fn activities_far_off_the_target_are_rejected_test() {
  let scheduled = schedule([workout("w1", 1, plan.Long, Some(20_000.0), None)])
  assert matching.propose(
      scheduled,
      [run("short", "2026-10-06 06:00:00.000Z", 5000.0, 1500)],
      [],
      fixed(0),
    )
    == [Match("short", "w1", "a1")]
  assert matching.propose(
      scheduled,
      [run("huge", "2026-10-06 06:00:00.000Z", 42_195.0, 14_000)],
      [],
      fixed(0),
    )
    == []
  assert matching.propose(
      scheduled,
      [run("tiny", "2026-10-06 06:00:00.000Z", 0.0, 60)],
      [],
      fixed(0),
    )
    == [Match("tiny", "w1", "a1")]
}

pub fn the_duration_target_is_used_without_a_distance_test() {
  let scheduled = schedule([workout("w1", 1, plan.Easy, None, Some(3600))])
  assert matching.propose(
      scheduled,
      [run("ok", "2026-10-06 06:00:00.000Z", 9000.0, 3500)],
      [],
      fixed(0),
    )
    == [Match("ok", "w1", "a1")]
  assert matching.propose(
      scheduled,
      [run("long", "2026-10-06 06:00:00.000Z", 30_000.0, 9000)],
      [],
      fixed(0),
    )
    == []
}

pub fn the_closest_activity_wins_and_is_used_once_test() {
  let scheduled = schedule([workout("w1", 1, plan.Easy, Some(10_000.0), None)])
  let acts = [
    run("far", "2026-10-06 06:00:00.000Z", 6000.0, 2000),
    run("close", "2026-10-06 17:00:00.000Z", 9800.0, 3200),
  ]
  assert matching.propose(scheduled, acts, [], fixed(0))
    == [Match("close", "w1", "a1")]
}

pub fn two_workouts_on_one_day_get_one_activity_each_test() {
  let scheduled =
    schedule([
      workout("short", 1, plan.Easy, Some(5000.0), None),
      workout("long", 1, plan.Long, Some(15_000.0), None),
    ])
  let acts = [
    run("a-15k", "2026-10-06 06:00:00.000Z", 15_100.0, 5000),
    run("b-5k", "2026-10-06 18:00:00.000Z", 4900.0, 1600),
  ]
  assert matching.propose(scheduled, acts, [], fixed(0))
    == [Match("a-15k", "long", "a1"), Match("b-5k", "short", "a1")]
}

pub fn one_activity_cannot_fill_two_workouts_test() {
  let scheduled =
    schedule([
      workout("w1", 1, plan.Easy, Some(8000.0), None),
      workout("w2", 1, plan.Easy, Some(8000.0), None),
    ])
  let acts = [run("only", "2026-10-06 06:00:00.000Z", 8000.0, 2500)]
  let result = matching.propose(scheduled, acts, [], fixed(0))
  assert result == [Match("only", "w1", "a1")]
}

pub fn existing_matches_are_kept_out_of_the_proposal_test() {
  let scheduled =
    schedule([
      workout("w1", 1, plan.Easy, Some(8000.0), None),
      workout("w2", 2, plan.Easy, Some(8000.0), None),
    ])
  let acts = [
    run("x", "2026-10-06 06:00:00.000Z", 8000.0, 2500),
    run("y", "2026-10-07 06:00:00.000Z", 8000.0, 2500),
  ]
  let existing = [Match("x", "w1", "a1")]
  assert matching.propose(scheduled, acts, existing, fixed(0))
    == [Match("y", "w2", "a1")]
  // A user who moved activity x to w2 by hand: x is taken, so w1 stays open and y has no workout left.
  let moved = [Match("x", "w2", "a1")]
  assert matching.propose(scheduled, acts, moved, fixed(0)) == []
}

pub fn the_same_plan_assigned_twice_is_matched_per_assignment_test() {
  let w = workout("w1", 1, plan.Easy, Some(8000.0), None)
  let first = plan.schedule(Assignment("a1", "p1", "alice", start), [w])
  let second = plan.schedule(Assignment("a2", "p1", "alice", start), [w])
  let acts = [
    run("x", "2026-10-06 06:00:00.000Z", 8000.0, 2500),
    run("y", "2026-10-06 18:00:00.000Z", 8000.0, 2500),
  ]
  let matches = matching.propose(list_append(first, second), acts, [], fixed(0))
  assert matches == [Match("x", "w1", "a1"), Match("y", "w1", "a2")]
}

fn list_append(a: List(Scheduled), b: List(Scheduled)) -> List(Scheduled) {
  case a {
    [] -> b
    [x, ..rest] -> [x, ..list_append(rest, b)]
  }
}

pub fn the_result_does_not_depend_on_input_order_test() {
  let scheduled =
    schedule([
      workout("w1", 1, plan.Easy, Some(8000.0), None),
      workout("w2", 1, plan.Easy, Some(8000.0), None),
    ])
  let a = run("a", "2026-10-06 06:00:00.000Z", 8000.0, 2500)
  let b = run("b", "2026-10-06 18:00:00.000Z", 8000.0, 2500)
  assert matching.propose(scheduled, [a, b], [], fixed(0))
    == matching.propose(scheduled, [b, a], [], fixed(0))
}

pub fn bad_timestamps_are_ignored_test() {
  let scheduled = schedule([workout("w1", 1, plan.Easy, None, None)])
  assert matching.propose(
      scheduled,
      [run("bad", "yesterday", 8000.0, 2500)],
      [],
      fixed(0),
    )
    == []
}

pub fn status_test() {
  let scheduled =
    schedule([
      workout("done", 0, plan.Easy, None, None),
      workout("missed", 1, plan.Easy, None, None),
      workout("today", 2, plan.Easy, None, None),
      workout("later", 3, plan.Easy, None, None),
      workout("rest", 1, plan.Rest, None, None),
    ])
  let matches = [Match("act1", "done", "a1")]
  let today = Date(2026, 10, 7)
  let status = fn(id) {
    let assert Ok(s) = find(scheduled, id)
    matching.status(s, matches, today)
  }
  assert status("done") == Done("act1")
  assert status("missed") == Missed
  assert status("today") == Planned
  assert status("later") == Planned
  assert status("rest") == RestDay
}

fn find(scheduled: List(Scheduled), id: String) -> Result(Scheduled, Nil) {
  case scheduled {
    [] -> Error(Nil)
    [s, ..rest] ->
      case s.workout.id == id {
        True -> Ok(s)
        False -> find(rest, id)
      }
  }
}

pub fn a_match_for_another_assignment_does_not_count_test() {
  let scheduled = schedule([workout("w1", 0, plan.Easy, None, None)])
  let assert [s] = scheduled
  assert matching.status(s, [Match("x", "w1", "other")], Date(2026, 10, 10))
    == Missed
}

/// Swiss time: UTC+1 until 01:00 UTC on 2026-03-29, UTC+2 after.
fn zurich(timestamp: String) -> Int {
  case string.compare(timestamp, "2026-03-29 01:00:00.000Z") {
    order.Lt -> 60
    _ -> 120
  }
}

pub fn the_offset_that_applied_at_the_time_decides_the_day_test() {
  // 22:30 UTC on 29 March is 00:30 on the 30th once summer time has started.
  let plan_start = Date(2026, 3, 30)
  let scheduled =
    plan.schedule(Assignment("a1", "p1", "alice", plan_start), [
      workout("w1", 0, plan.Easy, Some(8000.0), None),
    ])
  let acts = [run("late", "2026-03-29 22:30:00.000Z", 8000.0, 2500)]
  assert matching.propose(scheduled, acts, [], zurich)
    == [Match("late", "w1", "a1")]
  // With the winter offset for everything, the same run would have landed on the 29th.
  assert matching.propose(scheduled, acts, [], fixed(60)) == []
}

pub fn runs_before_and_after_the_change_each_get_their_own_offset_test() {
  let scheduled =
    plan.schedule(Assignment("a1", "p1", "alice", Date(2026, 3, 28)), [
      workout("sat", 0, plan.Easy, Some(8000.0), None),
      workout("sun", 1, plan.Easy, Some(8000.0), None),
      workout("mon", 2, plan.Easy, Some(8000.0), None),
    ])
  let acts = [
    // 23:30 UTC on the 27th: 00:30 on the 28th (winter time).
    run("a", "2026-03-27 23:30:00.000Z", 8000.0, 2500),
    // Midday on the 28th, winter time.
    run("b", "2026-03-28 12:00:00.000Z", 8000.0, 2500),
    // 22:30 UTC on the 29th: 00:30 on the 30th (summer time).
    run("c", "2026-03-29 22:30:00.000Z", 8000.0, 2500),
  ]
  let matches = matching.propose(scheduled, acts, [], zurich)
  assert list.contains(matches, Match("c", "mon", "a1"))
}
