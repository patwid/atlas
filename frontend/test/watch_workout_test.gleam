import atlas/pace_zones
import atlas/plan.{GoalPace, Intervals, Segment, Set, Workout}
import atlas/watch_workout.{
  Active, Cooldown, Distance, LapPress, Open, Pace, Recovery, Repeat, Step, Time,
  Warmup,
}
import atlas/workout_form.{Row}
import gleam/option.{None, Some}

/// Threshold 5:00 /km: zone 1 is 7:00-6:28, zone 4 5:18-4:58 and zone 5 from 4:57.
fn zones() {
  pace_zones.defaults(300)
}

fn row(kind, distance, duration, zone, intervals) {
  Row(
    Workout("w1", "p1", 0, 0, "Track", kind, distance, duration),
    "",
    intervals,
    zone,
    "",
  )
}

fn segment(zone, distance, duration) {
  Segment(zone, distance, duration, None)
}

pub fn a_run_ends_on_its_distance_at_its_zone_test() {
  let assert [Step(Active, Distance(10_000.0), Pace(420, 388))] =
    watch_workout.steps(
      row(plan.Run, Some(10_000.0), Some(3600), 1, None),
      zones(),
    )
}

pub fn a_run_without_a_distance_ends_on_its_time_test() {
  let assert [Step(Active, Time(3600), Open)] =
    watch_workout.steps(row(plan.Run, None, Some(3600), 0, None), zones())
}

pub fn a_run_without_either_ends_on_a_lap_press_test() {
  let assert [Step(Active, LapPress, Open)] =
    watch_workout.steps(row(plan.Run, None, None, 0, None), zones())
}

pub fn a_rest_day_has_no_steps_test() {
  let assert [] =
    watch_workout.steps(row(plan.Rest, None, None, 0, None), zones())
  let assert False = watch_workout.can_export(plan.Rest)
  let assert True = watch_workout.can_export(plan.Interval)
}

pub fn a_race_has_its_warm_up_and_cool_down_by_the_clock_test() {
  let parts = Intervals(segment(1, 2000.0, 900), [], segment(0, 1000.0, 0))
  let assert [
    Step(Warmup, Time(900), Pace(420, 388)),
    Step(Active, Distance(10_000.0), Pace(297, 120)),
    Step(Cooldown, Distance(1000.0), Open),
  ] =
    watch_workout.steps(
      row(plan.Race, Some(10_000.0), Some(2400), 5, Some(parts)),
      zones(),
    )
}

pub fn intervals_repeat_each_set_without_a_recovery_after_the_last_rep_test() {
  let parts =
    Intervals(
      segment(1, 0.0, 900),
      [
        Set(2, segment(4, 400.0, 80), segment(1, 200.0, 60)),
        Set(6, segment(4, 800.0, 170), segment(1, 0.0, 90)),
      ],
      segment(1, 0.0, 600),
    )
  let assert [
    Step(Warmup, Time(900), Pace(420, 388)),
    Step(Active, Distance(400.0), Pace(318, 298)),
    Step(Recovery, Time(60), Pace(420, 388)),
    Repeat(1, 2),
    Step(Active, Distance(800.0), Pace(318, 298)),
    Step(Recovery, Time(90), Pace(420, 388)),
    Repeat(4, 5),
    Step(Active, Distance(800.0), Pace(318, 298)),
    Step(Cooldown, Time(600), Pace(420, 388)),
  ] =
    watch_workout.steps(row(plan.Interval, None, None, 4, Some(parts)), zones())
}

pub fn sets_of_one_rep_and_sets_without_recovery_have_no_repeat_or_recovery_test() {
  let parts =
    Intervals(
      plan.no_segment,
      [
        Set(1, segment(0, 1000.0, 0), segment(0, 0.0, 120)),
        Set(4, segment(0, 0.0, 30), plan.no_segment),
        // Not runnable: no distance or time.
        Set(3, segment(4, 0.0, 0), plan.no_segment),
        Set(2, segment(0, 200.0, 0), segment(0, 0.0, 60)),
        Set(1, segment(0, 100.0, 0), segment(0, 0.0, 60)),
      ],
      plan.no_segment,
    )
  let assert [
    Step(Active, Distance(1000.0), Open),
    Step(Recovery, Time(120), Open),
    Step(Active, Time(30), Open),
    Repeat(2, 4),
    Step(Active, Distance(200.0), Open),
    Step(Recovery, Time(60), Open),
    Repeat(4, 2),
    Step(Active, Distance(100.0), Open),
  ] =
    watch_workout.steps(row(plan.Interval, None, None, 0, Some(parts)), zones())
}

pub fn the_last_set_of_two_reps_ends_with_a_rep_not_a_repeat_test() {
  let parts =
    Intervals(
      plan.no_segment,
      [Set(2, segment(0, 400.0, 0), segment(0, 0.0, 60))],
      plan.no_segment,
    )
  let assert [
    Step(Active, Distance(400.0), Open),
    Step(Recovery, Time(60), Open),
    Step(Active, Distance(400.0), Open),
  ] =
    watch_workout.steps(row(plan.Interval, None, None, 0, Some(parts)), zones())
}

pub fn a_rep_at_a_race_goal_gets_its_pace_within_five_seconds_test() {
  // 10 km in 40:00 is 4:00 /km; at 90 % 4:27 /km.
  let goal = Some(GoalPace("g1", 10_000.0, 2400, 90))
  let parts =
    Intervals(
      plan.no_segment,
      [Set(1, Segment(0, 1000.0, 0, goal), plan.no_segment)],
      plan.no_segment,
    )
  let assert [Step(Active, Distance(1000.0), Pace(272, 262))] =
    watch_workout.steps(row(plan.Interval, None, None, 0, Some(parts)), zones())
}
