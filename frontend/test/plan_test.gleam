import atlas/date.{type Date, Date}
import atlas/plan.{
  type Workout, Assignment, Interval, Rest, Run, Scheduled, WeekTotal, Workout,
}
import gleam/option.{None, Some}

fn workout(id: String, day: Int, kind: plan.Kind) -> Workout {
  Workout(id, "p1", day, 0, id, kind, None, None)
}

fn assignment(start: Date) -> plan.Assignment {
  Assignment("a1", "p1", "alice", Some(start))
}

/// The schedule of an assignment with its own start date.
fn schedule(start: Date, workouts: List(Workout)) -> List(plan.Scheduled) {
  plan.schedule(assignment(start), start, workouts)
}

pub fn kinds_round_trip_test() {
  let kinds = [plan.Run, plan.Interval, plan.Race, plan.Rest]
  assert list_map(kinds) == kinds
  assert plan.kind_to_string(plan.Run) == "run"
  assert plan.kind_from_string("jogging") == Error(Nil)
}

pub fn the_kinds_before_0114_are_read_as_a_run_test() {
  assert plan.kind_from_string("easy") == Ok(plan.Run)
  assert plan.kind_from_string("long") == Ok(plan.Run)
  assert plan.kind_from_string("tempo") == Ok(plan.Run)
  assert plan.kind_from_string("cross") == Ok(plan.Run)
  assert plan.kind_from_string("strength") == Ok(plan.Run)
}

fn list_map(kinds: List(plan.Kind)) -> List(plan.Kind) {
  case kinds {
    [] -> []
    [k, ..rest] -> {
      let assert Ok(back) = plan.kind_from_string(plan.kind_to_string(k))
      [back, ..list_map(rest)]
    }
  }
}

pub fn workout_dates_count_from_the_monday_of_the_start_week_test() {
  // Wednesday 28 Oct: day 0 is Monday 26 Oct.
  let start = Date(2026, 10, 28)
  assert plan.first_monday(start) == Date(2026, 10, 26)
  assert plan.first_day(start) == 2
  assert plan.first_day(Date(2026, 10, 26)) == 0
  assert plan.first_day(Date(2026, 11, 1)) == 6
  assert plan.workout_date(start, workout("w", 0, Run)) == Date(2026, 10, 26)
  assert plan.workout_date(start, workout("w", 7, Run)) == Date(2026, 11, 2)
  assert plan.workout_date(start, workout("w", 70, Run)) == Date(2027, 1, 4)
}

pub fn moving_the_start_within_its_week_keeps_every_date_test() {
  let w = workout("w", 13, Run)
  assert plan.workout_date(Date(2026, 10, 26), w)
    == plan.workout_date(Date(2026, 10, 30), w)
  // A week later moves it by a week, on the same weekday.
  assert plan.workout_date(Date(2026, 11, 2), w) == Date(2026, 11, 15)
}

pub fn an_assignment_starts_on_its_own_date_or_its_plans_test() {
  let dated =
    plan.Plan(
      ..plan.new("p1", "me", "10k", "", "T"),
      start_date: Some(Date(2026, 11, 2)),
    )
  let undated = plan.new("p2", "me", "Old", "", "T")
  let following = Assignment("a1", "p1", "me", None)
  assert plan.start_of(following, [undated, dated]) == Ok(Date(2026, 11, 2))
  assert plan.start_of(Assignment("a1", "p1", "me", Some(Date(2026, 12, 7))), [
      dated,
    ])
    == Ok(Date(2026, 12, 7))
  assert plan.start_of(Assignment("a2", "p2", "me", None), [undated])
    == Error(Nil)
  assert plan.start_of(following, []) == Error(Nil)
}

pub fn the_coming_monday_test() {
  assert plan.coming_monday(Date(2026, 10, 12)) == Date(2026, 10, 12)
  assert plan.coming_monday(Date(2026, 10, 11)) == Date(2026, 10, 12)
  assert plan.coming_monday(Date(2026, 10, 13)) == Date(2026, 10, 19)
}

pub fn schedule_is_ordered_and_ignores_other_plans_test() {
  let other = Workout("x", "other-plan", 0, 0, "x", Run, None, None)
  let second_same_day = Workout("w3", "p1", 2, 1, "w3", Run, None, None)
  let first_same_day = Workout("w2", "p1", 2, 0, "w2", Run, None, None)
  let scheduled =
    schedule(Date(2026, 10, 5), [
      second_same_day,
      workout("w4", 5, Run),
      other,
      first_same_day,
      workout("w1", 0, Run),
    ])
  assert list_ids(scheduled) == ["w1", "w2", "w3", "w4"]
  assert case scheduled {
    [Scheduled("a1", Date(2026, 10, 5), _), ..] -> True
    _ -> False
  }
}

pub fn the_days_before_the_start_are_left_out_test() {
  // Thursday 8 Oct: Monday to Wednesday of that week are not part of the plan.
  let scheduled =
    schedule(Date(2026, 10, 8), [
      workout("mon", 0, Run),
      workout("wed", 2, Run),
      workout("thu", 3, Run),
      workout("next-mon", 7, Run),
    ])
  assert list_ids(scheduled) == ["thu", "next-mon"]
  assert case scheduled {
    [Scheduled(_, Date(2026, 10, 8), _), ..] -> True
    _ -> False
  }
}

fn list_ids(scheduled: List(plan.Scheduled)) -> List(String) {
  case scheduled {
    [] -> []
    [s, ..rest] -> [s.workout.id, ..list_ids(rest)]
  }
}

pub fn ties_break_by_id_so_the_order_is_stable_test() {
  let start = Date(2026, 10, 5)
  let one = schedule(start, [workout("b", 1, Run), workout("a", 1, Run)])
  let two = schedule(start, [workout("a", 1, Run), workout("b", 1, Run)])
  assert list_ids(one) == ["a", "b"]
  assert list_ids(two) == ["a", "b"]
}

pub fn length_and_end_date_test() {
  let start = Date(2026, 10, 7)
  let no_phases = plan.Phases(0, 0, 0)
  assert plan.length_days([]) == 0
  assert plan.length_days([workout("w", 0, Run)]) == 1
  assert plan.length_days([workout("w", 27, Run), workout("v", 3, Run)]) == 28
  // The plan ends on the Sunday of its last week: of the last workout here, Sunday 1 Nov.
  assert plan.end_date(start, no_phases, [workout("w", 23, Run)])
    == Ok(Date(2026, 11, 1))
  assert plan.end_date(start, no_phases, []) == Error(Nil)
  // Or of the last phase week, when that is later: 2 + 1 + 1 weeks from Monday 5 Oct.
  assert plan.end_date(start, plan.Phases(2, 1, 1), [workout("w", 3, Run)])
    == Ok(Date(2026, 11, 1))
  assert plan.week_count(plan.Phases(2, 1, 1), [workout("w", 40, Run)]) == 6
}

pub fn on_date_test() {
  let scheduled =
    schedule(Date(2026, 10, 5), [
      workout("w1", 0, Run),
      workout("w2", 1, Run),
      workout("w3", 1, Run),
    ])
  assert list_ids(plan.on_date(scheduled, Date(2026, 10, 6))) == ["w2", "w3"]
  assert plan.on_date(scheduled, Date(2026, 10, 9)) == []
}

pub fn weekly_totals_test() {
  // Wednesday start: days 2-6 fall in the first week (Mon 5 Oct), day 7 onwards in the next.
  let workouts = [
    Workout("w1", "p1", 2, 0, "w1", Run, Some(8000.0), Some(2700)),
    Workout("w2", "p1", 4, 0, "w2", Interval, Some(6000.0), None),
    Workout("w3", "p1", 6, 0, "w3", Rest, None, None),
    Workout("w4", "p1", 7, 0, "w4", Run, Some(20_000.0), Some(7200)),
  ]
  assert plan.weekly_totals(schedule(Date(2026, 10, 7), workouts))
    == [
      WeekTotal(Date(2026, 10, 5), 2, 14_000.0, 2700),
      WeekTotal(Date(2026, 10, 12), 1, 20_000.0, 7200),
    ]
  assert plan.weekly_totals([]) == []
}

pub fn rest_days_add_no_workouts_test() {
  assert plan.weekly_totals(
      schedule(Date(2026, 10, 5), [workout("r", 0, Rest)]),
    )
    == [WeekTotal(Date(2026, 10, 5), 0, 0.0, 0)]
}

fn track() -> plan.Intervals {
  plan.Intervals(
    plan.Segment(1, 2000.0, 600, None),
    [
      plan.Set(
        3,
        plan.Segment(4, 800.0, 180, None),
        plan.Segment(1, 200.0, 90, None),
      ),
      plan.Set(0, plan.no_segment, plan.no_segment),
    ],
    plan.Segment(1, 1000.0, 300, None),
  )
}

pub fn an_interval_workouts_totals_are_those_of_its_parts_test() {
  // 2 km + 3 × 800 m + 2 × 200 m + 1 km, and 10 min + 3 × 3 min + 2 × 1:30 + 5 min: no recovery after the last rep.
  assert plan.interval_totals(track()) == #(5800.0, 1620)
  assert plan.interval_totals(plan.Intervals(
      plan.no_segment,
      [],
      plan.no_segment,
    ))
    == #(0.0, 0)
}

pub fn an_interval_workouts_targets_are_those_of_its_parts_test() {
  let w = workout("w", 0, Interval)
  let totals = Workout(..w, distance_m: Some(5800.0), duration_s: Some(1620))
  assert plan.with_totals(w, Some(track())) == totals
  // What was saved as its own, such as before ADR 0130, is not counted.
  let own = Workout(..w, distance_m: Some(6000.0), duration_s: Some(2400))
  assert plan.with_totals(own, Some(track())) == totals
  // Parts without a distance or time add none.
  let empty = plan.Intervals(plan.no_segment, [], plan.no_segment)
  assert plan.with_totals(own, Some(empty)) == w
  // Without parts, it keeps its own.
  assert plan.with_totals(own, None) == own
  // Only intervals: a race's warm-up and cool-down are not the race.
  let race = workout("r", 0, plan.Race)
  assert plan.with_totals(race, Some(track())) == race
}
