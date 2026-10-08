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

const no_phases = plan.Phases(0, 0, 0)

pub fn the_weeks_of_the_phases_are_there_also_without_workouts_test() {
  let weeks = plan_schedule.weeks(plan.Phases(2, 1, 1), [])
  assert list.map(weeks, fn(week) { week.number }) == [1, 2, 3, 4]
  assert list.map(weeks, fn(week) { week.phase })
    == [
      Ok(#(plan.Base, 1)),
      Ok(#(plan.Base, 2)),
      Ok(#(plan.PreCompetition, 1)),
      Ok(#(plan.Competition, 1)),
    ]
}

pub fn workouts_after_the_phases_add_weeks_without_a_phase_test() {
  let weeks = plan_schedule.weeks(plan.Phases(1, 0, 1), [w("a", 20, 0, 1.0, 1)])
  assert list.length(weeks) == 3
  let assert Ok(last) = list.last(weeks)
  assert last.phase == Error(Nil)
  assert list.map(plan_schedule.bands(weeks), fn(band) {
      #(band.phase, list.map(band.weeks, fn(week) { week.number }))
    })
    == [
      #(Ok(plan.Base), [1]),
      #(Ok(plan.Competition), [2]),
      #(Error(Nil), [3]),
    ]
}

pub fn weeks_are_named_by_their_phase_test() {
  let phases = plan.Phases(4, 4, 4)
  assert plan_schedule.week_label(phases, 1) == "Base, week 1"
  assert plan_schedule.week_label(phases, 6) == "Pre-competition, week 2"
  assert plan_schedule.week_label(phases, 12) == "Competition, week 4"
  assert plan_schedule.week_label(phases, 13) == "Week 13"
  assert plan_schedule.week_label(no_phases, 2) == "Week 2"
}

pub fn a_week_is_measured_against_the_goal_test() {
  let assert [week] =
    plan_schedule.weeks(no_phases, [
      w("a", 0, 0, 10_000.0, 1),
      w("b", 2, 0, 20_000.0, 1),
    ])
  assert plan_schedule.goal_share(week, Some(40_000.0)) == Ok(0.75)
  assert plan_schedule.goal_share(week, None) == Error(Nil)
}

pub fn an_empty_plan_has_no_weeks_test() {
  assert plan_schedule.weeks(no_phases, []) == []
}

pub fn weeks_run_from_the_first_to_the_last_workout_with_empty_days_test() {
  let weeks =
    plan_schedule.weeks(no_phases, [
      w("a", 0, 0, 5000.0, 1800),
      w("b", 8, 0, 8000.0, 2700),
    ])
  assert list.length(weeks) == 2
  let assert [first, second] = weeks
  assert first.number == 1
  assert second.number == 2
  assert list.length(first.days) == 7
  assert list.map(first.days, fn(d) { d.number }) == [1, 2, 3, 4, 5, 6, 7]
  assert list.map(second.days, fn(d) { d.index }) == [7, 8, 9, 10, 11, 12, 13]
}

pub fn a_workout_on_day_seven_stays_in_the_first_week_test() {
  let weeks = plan_schedule.weeks(no_phases, [w("a", 6, 0, 1.0, 1)])
  assert list.length(weeks) == 1
  let assert [Week(_, days, _, _, _)] = weeks
  let assert Ok(Day(7, 6, [found])) = list.last(days)
  assert found.id == "a"
}

pub fn the_first_day_of_the_eighth_day_starts_a_new_week_test() {
  assert list.length(plan_schedule.weeks(no_phases, [w("a", 7, 0, 1.0, 1)]))
    == 2
}

pub fn workouts_on_a_day_are_in_position_order_test() {
  let weeks =
    plan_schedule.weeks(no_phases, [
      w("z", 0, 0, 1.0, 1),
      w("a", 0, 1, 1.0, 1),
      w("m", 0, 0, 1.0, 1),
    ])
  let assert [Week(_, [Day(_, _, ids), ..], _, _, _)] = weeks
  // Equal positions fall back to the ID, so the order is stable.
  assert list.map(ids, fn(x) { x.id }) == ["m", "z", "a"]
}

pub fn weekly_totals_add_up_distance_and_time_test() {
  let weeks =
    plan_schedule.weeks(no_phases, [
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
