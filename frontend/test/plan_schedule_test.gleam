import atlas/plan.{type Workout, Workout}
import atlas/plan_schedule.{Day, Week}
import gleam/list
import gleam/option.{None, Some}

fn w(
  id: String,
  day: Int,
  position: Int,
  distance: Float,
  seconds: Int,
) -> Workout {
  Workout(id, "p1", day, position, id, plan.Easy, Some(distance), Some(seconds))
}

pub fn an_empty_plan_has_no_weeks_test() {
  assert plan_schedule.weeks([]) == []
}

pub fn weeks_run_from_the_first_to_the_last_workout_with_empty_days_test() {
  let weeks =
    plan_schedule.weeks([w("a", 0, 0, 5000.0, 1800), w("b", 8, 0, 8000.0, 2700)])
  assert list.length(weeks) == 2
  let assert [first, second] = weeks
  assert first.number == 1
  assert second.number == 2
  assert list.length(first.days) == 7
  assert list.map(first.days, fn(d) { d.number }) == [1, 2, 3, 4, 5, 6, 7]
  assert list.map(second.days, fn(d) { d.index }) == [7, 8, 9, 10, 11, 12, 13]
}

pub fn a_workout_on_day_seven_stays_in_the_first_week_test() {
  let weeks = plan_schedule.weeks([w("a", 6, 0, 1.0, 1)])
  assert list.length(weeks) == 1
  let assert [Week(_, days, _, _)] = weeks
  let assert Ok(Day(7, 6, [found])) = list.last(days)
  assert found.id == "a"
}

pub fn the_first_day_of_the_eighth_day_starts_a_new_week_test() {
  assert list.length(plan_schedule.weeks([w("a", 7, 0, 1.0, 1)])) == 2
}

pub fn workouts_on_a_day_are_in_position_order_test() {
  let weeks =
    plan_schedule.weeks([
      w("z", 0, 0, 1.0, 1),
      w("a", 0, 1, 1.0, 1),
      w("m", 0, 0, 1.0, 1),
    ])
  let assert [Week(_, [Day(_, _, ids), ..], _, _)] = weeks
  // Equal positions fall back to the ID, so the order is stable.
  assert list.map(ids, fn(x) { x.id }) == ["m", "z", "a"]
}

pub fn weekly_totals_add_up_distance_and_time_test() {
  let weeks =
    plan_schedule.weeks([
      w("a", 0, 0, 5000.0, 1800),
      w("b", 2, 0, 8000.0, 2700),
      w("c", 7, 0, 20_000.0, 7200),
      Workout("d", "p1", 3, 0, "d", plan.Rest, None, None),
    ])
  let assert [one, two] = weeks
  assert one.distance_m == 13_000.0
  assert one.duration_s == 4500
  assert two.distance_m == 20_000.0
  assert two.duration_s == 7200
}

pub fn the_next_position_is_after_the_last_one_on_that_day_test() {
  let workouts = [
    w("a", 0, 0, 1.0, 1),
    w("b", 0, 1, 1.0, 1),
    w("c", 3, 5, 1.0, 1),
  ]
  assert plan_schedule.next_position(workouts, 0) == 2
  assert plan_schedule.next_position(workouts, 3) == 6
  assert plan_schedule.next_position(workouts, 1) == 0
  assert plan_schedule.next_position([], 0) == 0
}
