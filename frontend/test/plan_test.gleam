import atlas/date.{type Date, Date}
import atlas/plan.{
  type Workout, Assignment, Easy, Interval, Long, Rest, Scheduled, WeekTotal,
  Workout,
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
  let kinds = [
    plan.Easy,
    plan.Long,
    plan.Tempo,
    plan.Interval,
    plan.Race,
    plan.Rest,
    plan.Cross,
    plan.Strength,
  ]
  assert list_map(kinds) == kinds
  assert plan.kind_from_string("jogging") == Error(Nil)
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
  assert plan.workout_date(start, workout("w", 0, Easy)) == Date(2026, 10, 26)
  assert plan.workout_date(start, workout("w", 7, Easy)) == Date(2026, 11, 2)
  assert plan.workout_date(start, workout("w", 70, Easy)) == Date(2027, 1, 4)
}

pub fn moving_the_start_within_its_week_keeps_every_date_test() {
  let w = workout("w", 13, Long)
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
  let other = Workout("x", "other-plan", 0, 0, "x", Easy, None, None)
  let second_same_day = Workout("w3", "p1", 2, 1, "w3", Easy, None, None)
  let first_same_day = Workout("w2", "p1", 2, 0, "w2", Easy, None, None)
  let scheduled =
    schedule(Date(2026, 10, 5), [
      second_same_day,
      workout("w4", 5, Long),
      other,
      first_same_day,
      workout("w1", 0, Easy),
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
      workout("mon", 0, Easy),
      workout("wed", 2, Easy),
      workout("thu", 3, Easy),
      workout("next-mon", 7, Easy),
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
  let one = schedule(start, [workout("b", 1, Easy), workout("a", 1, Easy)])
  let two = schedule(start, [workout("a", 1, Easy), workout("b", 1, Easy)])
  assert list_ids(one) == ["a", "b"]
  assert list_ids(two) == ["a", "b"]
}

pub fn length_and_end_date_test() {
  let start = Date(2026, 10, 7)
  let no_phases = plan.Phases(0, 0, 0)
  assert plan.length_days([]) == 0
  assert plan.length_days([workout("w", 0, Easy)]) == 1
  assert plan.length_days([workout("w", 27, Long), workout("v", 3, Easy)]) == 28
  // The plan ends on the Sunday of its last week: of the last workout here, Sunday 1 Nov.
  assert plan.end_date(start, no_phases, [workout("w", 23, Long)])
    == Ok(Date(2026, 11, 1))
  assert plan.end_date(start, no_phases, []) == Error(Nil)
  // Or of the last phase week, when that is later: 2 + 1 + 1 weeks from Monday 5 Oct.
  assert plan.end_date(start, plan.Phases(2, 1, 1), [workout("w", 3, Easy)])
    == Ok(Date(2026, 11, 1))
  assert plan.week_count(plan.Phases(2, 1, 1), [workout("w", 40, Easy)]) == 6
}

pub fn on_date_test() {
  let scheduled =
    schedule(Date(2026, 10, 5), [
      workout("w1", 0, Easy),
      workout("w2", 1, Long),
      workout("w3", 1, Easy),
    ])
  assert list_ids(plan.on_date(scheduled, Date(2026, 10, 6))) == ["w2", "w3"]
  assert plan.on_date(scheduled, Date(2026, 10, 9)) == []
}

pub fn weekly_totals_test() {
  // Wednesday start: days 2-6 fall in the first week (Mon 5 Oct), day 7 onwards in the next.
  let workouts = [
    Workout("w1", "p1", 2, 0, "w1", Easy, Some(8000.0), Some(2700)),
    Workout("w2", "p1", 4, 0, "w2", Interval, Some(6000.0), None),
    Workout("w3", "p1", 6, 0, "w3", Rest, None, None),
    Workout("w4", "p1", 7, 0, "w4", Long, Some(20_000.0), Some(7200)),
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
