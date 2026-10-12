import atlas/date.{Date}
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
  Workout(id, "p1", day, position, id, plan.Run, Some(distance), Some(seconds))
}

const no_phases = plan.Phases(0, 0, 0)

pub fn the_weeks_of_the_phases_are_there_also_without_workouts_test() {
  let weeks = plan_schedule.weeks(plan.Phases(2, 1, 1), None, [])
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
  let weeks =
    plan_schedule.weeks(plan.Phases(1, 0, 1), None, [w("a", 20, 0, 1.0, 1)])
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
  assert plan_schedule.week_label(phases, None, 1) == "Week 1 · Base 1"
  assert plan_schedule.week_label(phases, None, 6)
    == "Week 6 · Pre-competition 2"
  assert plan_schedule.week_label(phases, None, 12) == "Week 12 · Competition 4"
  assert plan_schedule.week_label(phases, None, 13) == "Week 13"
  assert plan_schedule.week_label(no_phases, None, 2) == "Week 2"
}

pub fn a_dated_plans_weeks_are_named_by_their_week_of_the_year_test() {
  let phases = plan.Phases(4, 4, 4)
  // 4 Nov 2026 is a Wednesday of ISO week 45.
  let start = Some(Date(2026, 11, 4))
  assert plan_schedule.week_label(phases, start, 1) == "Week 45 · Base 1"
  assert plan_schedule.week_label(phases, start, 6)
    == "Week 50 · Pre-competition 2"
  // Across the new year: 28 Dec 2026 is in week 53, and the weeks start over in 2027.
  assert plan_schedule.week_name(start, 8) == "Week 52"
  assert plan_schedule.week_name(start, 9) == "Week 53"
  assert plan_schedule.week_name(start, 10) == "Week 1"
  let assert [first, ..] = plan_schedule.weeks(phases, start, [])
  assert first.name == "Week 45"
}

pub fn a_week_is_measured_against_the_goal_test() {
  let assert [week] =
    plan_schedule.weeks(no_phases, None, [
      w("a", 0, 0, 10_000.0, 1),
      w("b", 2, 0, 20_000.0, 1),
    ])
  assert plan_schedule.goal_share(week, Some(40_000.0)) == Ok(0.75)
  assert plan_schedule.goal_share(week, None) == Error(Nil)
}

pub fn an_empty_plan_has_no_weeks_test() {
  assert plan_schedule.weeks(no_phases, None, []) == []
}

pub fn weeks_run_from_the_first_to_the_last_workout_with_empty_days_test() {
  let weeks =
    plan_schedule.weeks(no_phases, None, [
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
  let weeks = plan_schedule.weeks(no_phases, None, [w("a", 6, 0, 1.0, 1)])
  assert list.length(weeks) == 1
  let assert [Week(_, _, days, _, _, _)] = weeks
  let assert Ok(Day(7, 6, None, False, [found])) = list.last(days)
  assert found.id == "a"
}

pub fn the_first_day_of_the_eighth_day_starts_a_new_week_test() {
  assert list.length(
      plan_schedule.weeks(no_phases, None, [w("a", 7, 0, 1.0, 1)]),
    )
    == 2
}

pub fn workouts_on_a_day_are_in_position_order_test() {
  let weeks =
    plan_schedule.weeks(no_phases, None, [
      w("z", 0, 0, 1.0, 1),
      w("a", 0, 1, 1.0, 1),
      w("m", 0, 0, 1.0, 1),
    ])
  let assert [Week(_, _, [Day(_, _, _, _, ids), ..], _, _, _)] = weeks
  // Equal positions fall back to the ID, so the order is stable.
  assert list.map(ids, fn(x) { x.id }) == ["m", "z", "a"]
}

pub fn weekly_totals_add_up_distance_and_time_test() {
  let weeks =
    plan_schedule.weeks(no_phases, None, [
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

pub fn a_weeks_goal_follows_its_intensity_test() {
  assert plan_schedule.week_goal(Some(40_000.0), Ok(0.6)) == Some(24_000.0)
  assert plan_schedule.week_goal(Some(40_000.0), Error(Nil)) == Some(40_000.0)
  assert plan_schedule.week_goal(None, Ok(0.6)) == None
  // A week at 0% has no distance to reach: no share is shown.
  let assert [week] =
    plan_schedule.weeks(no_phases, None, [w("a", 0, 0, 10_000.0, 1)])
  assert plan_schedule.goal_share(
      week,
      plan_schedule.week_goal(Some(40_000.0), Ok(0.0)),
    )
    == Error(Nil)
}

pub fn with_a_start_date_every_day_has_its_date_from_monday_test() {
  // Wednesday 4 Nov 2026: Monday 2 and Tuesday 3 Nov are before the start.
  let assert [first, second] =
    plan_schedule.weeks(plan.Phases(2, 0, 0), Some(Date(2026, 11, 4)), [])
  assert list.map(first.days, fn(d) { d.date })
    == [
      Some(Date(2026, 11, 2)),
      Some(Date(2026, 11, 3)),
      Some(Date(2026, 11, 4)),
      Some(Date(2026, 11, 5)),
      Some(Date(2026, 11, 6)),
      Some(Date(2026, 11, 7)),
      Some(Date(2026, 11, 8)),
    ]
  assert list.map(first.days, fn(d) { d.before_start })
    == [True, True, False, False, False, False, False]
  assert list.all(second.days, fn(d) { !d.before_start })
  assert plan_schedule.week_dates(first) == Ok("2–8 Nov")
  assert plan_schedule.week_dates(second) == Ok("9–15 Nov")
  let assert [monday, ..] = first.days
  assert plan_schedule.day_name(monday) == "Mon 2 Nov"
}

pub fn without_a_start_date_days_have_weekdays_only_test() {
  let assert [week] = plan_schedule.weeks(plan.Phases(1, 0, 0), None, [])
  assert list.map(week.days, plan_schedule.day_name)
    == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
  assert list.all(week.days, fn(d) { !d.before_start })
  assert plan_schedule.week_dates(week) == Error(Nil)
}

pub fn a_week_across_months_and_years_names_both_ends_test() {
  let assert [_, across_months, ..] =
    plan_schedule.weeks(plan.Phases(6, 0, 0), Some(Date(2026, 11, 23)), [])
  assert plan_schedule.week_dates(across_months) == Ok("30 Nov – 6 Dec")
  let assert [across_years] =
    plan_schedule.weeks(plan.Phases(1, 0, 0), Some(Date(2026, 12, 28)), [])
  assert plan_schedule.week_dates(across_years)
    == Ok("28 Dec 2026 – 3 Jan 2027")
}
