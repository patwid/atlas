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
  Assignment("a1", "p1", "alice", start)
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

pub fn workout_dates_follow_the_start_date_test() {
  let a = assignment(Date(2026, 10, 26))
  assert plan.workout_date(a, workout("w", 0, Easy)) == Date(2026, 10, 26)
  assert plan.workout_date(a, workout("w", 7, Easy)) == Date(2026, 11, 2)
  assert plan.workout_date(a, workout("w", 70, Easy)) == Date(2027, 1, 4)
}

pub fn schedule_is_ordered_and_ignores_other_plans_test() {
  let a = assignment(Date(2026, 10, 5))
  let other = Workout("x", "other-plan", 0, 0, "x", Easy, None, None)
  let second_same_day = Workout("w3", "p1", 2, 1, "w3", Easy, None, None)
  let first_same_day = Workout("w2", "p1", 2, 0, "w2", Easy, None, None)
  let scheduled =
    plan.schedule(a, [
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

fn list_ids(scheduled: List(plan.Scheduled)) -> List(String) {
  case scheduled {
    [] -> []
    [s, ..rest] -> [s.workout.id, ..list_ids(rest)]
  }
}

pub fn ties_break_by_id_so_the_order_is_stable_test() {
  let a = assignment(Date(2026, 10, 5))
  let one = plan.schedule(a, [workout("b", 1, Easy), workout("a", 1, Easy)])
  let two = plan.schedule(a, [workout("a", 1, Easy), workout("b", 1, Easy)])
  assert list_ids(one) == ["a", "b"]
  assert list_ids(two) == ["a", "b"]
}

pub fn length_and_end_date_test() {
  let a = assignment(Date(2026, 10, 5))
  assert plan.length_days([]) == 0
  assert plan.length_days([workout("w", 0, Easy)]) == 1
  assert plan.length_days([workout("w", 27, Long), workout("v", 3, Easy)]) == 28
  assert plan.end_date(a, [workout("w", 27, Long)]) == Ok(Date(2026, 11, 1))
  assert plan.end_date(a, []) == Error(Nil)
  assert plan.end_date(a, [Workout("x", "other", 9, 0, "x", Easy, None, None)])
    == Error(Nil)
}

pub fn on_date_test() {
  let a = assignment(Date(2026, 10, 5))
  let scheduled =
    plan.schedule(a, [
      workout("w1", 0, Easy),
      workout("w2", 1, Long),
      workout("w3", 1, Easy),
    ])
  assert list_ids(plan.on_date(scheduled, Date(2026, 10, 6))) == ["w2", "w3"]
  assert plan.on_date(scheduled, Date(2026, 10, 9)) == []
}

pub fn weekly_totals_test() {
  let a = assignment(Date(2026, 10, 7))
  // Wednesday start: days 0-4 fall in the first week (Mon 5 Oct), day 5 onwards in the next.
  let workouts = [
    Workout("w1", "p1", 0, 0, "w1", Easy, Some(8000.0), Some(2700)),
    Workout("w2", "p1", 2, 0, "w2", Interval, Some(6000.0), None),
    Workout("w3", "p1", 4, 0, "w3", Rest, None, None),
    Workout("w4", "p1", 5, 0, "w4", Long, Some(20_000.0), Some(7200)),
  ]
  assert plan.weekly_totals(plan.schedule(a, workouts))
    == [
      WeekTotal(Date(2026, 10, 5), 2, 14_000.0, 2700),
      WeekTotal(Date(2026, 10, 12), 1, 20_000.0, 7200),
    ]
  assert plan.weekly_totals([]) == []
}

pub fn rest_days_add_no_workouts_test() {
  let a = assignment(Date(2026, 10, 5))
  assert plan.weekly_totals(plan.schedule(a, [workout("r", 0, Rest)]))
    == [WeekTotal(Date(2026, 10, 5), 0, 0.0, 0)]
}
