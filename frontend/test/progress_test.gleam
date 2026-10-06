import atlas/activity.{Activity}
import atlas/activity_form
import atlas/assignment_form
import atlas/date.{Date}
import atlas/matching.{Match, Stored}
import atlas/plan.{Assignment, Plan, Workout}
import atlas/progress.{Week}
import atlas/today.{Inputs}
import gleam/list
import gleam/option.{Some}

// Ana follows a plan that started on Monday 28 September. Today is Wednesday 7 October.
const monday = Date(2026, 9, 28)

const today = Date(2026, 10, 7)

fn workout(
  id: String,
  day: Int,
  kind: plan.Kind,
  distance: Float,
) -> plan.Workout {
  Workout(id, "p1", day, 0, id, kind, Some(distance), option.None)
}

fn run(
  id: String,
  owner: String,
  started: String,
  meters: Float,
) -> activity_form.Row {
  activity_form.Row(
    Activity(id, activity.Strava, started, activity.Run, meters, 1800),
    owner,
    "",
    0.0,
    0,
    "T",
  )
}

fn inputs() -> today.Inputs {
  Inputs(
    user_id: "ana",
    today: today,
    assignments: [
      assignment_form.Row(Assignment("a1", "p1", "ana", monday), "coach", "T"),
      assignment_form.Row(Assignment("a2", "p1", "ben", monday), "coach", "T"),
    ],
    workouts: [
      workout("mon1", 0, plan.Easy, 5000.0),
      workout("wed1", 2, plan.Tempo, 8000.0),
      workout("thu1", 3, plan.Rest, 0.0),
      workout("mon2", 7, plan.Easy, 6000.0),
      workout("wed2", 9, plan.Long, 10_000.0),
      workout("sat2", 12, plan.Easy, 5000.0),
    ],
    plans: [Plan("p1", "coach", "Base", "", plan.Private, "T")],
    activities: [
      run("x1", "ana", "2026-09-28 06:00:00.000Z", 5000.0),
      run("x2", "ana", "2026-10-05 06:00:00.000Z", 6000.0),
      run("x3", "ana", "2026-10-03 06:00:00.000Z", 3000.0),
      run("other", "ben", "2026-09-29 06:00:00.000Z", 9999.0),
    ],
    matches: [],
    offset_at: fn(_) { 0 },
  )
}

pub fn the_weeks_are_listed_newest_first_starting_on_mondays_test() {
  let weeks = progress.weeks(inputs(), 3)
  assert list.map(weeks, fn(w) { w.start })
    == [Date(2026, 10, 5), Date(2026, 9, 28), Date(2026, 9, 21)]
}

pub fn the_current_week_counts_what_is_done_and_what_is_still_to_come_test() {
  let assert [current, ..] = progress.weeks(inputs(), 3)
  // Monday's easy run is done; today's long run and Saturday's easy run are still to do, not missed.
  assert current == Week(Date(2026, 10, 5), 3, 1, 0, 21_000.0, 6000.0, 1)
}

pub fn a_past_week_counts_the_missed_workout_and_leaves_out_rest_days_test() {
  let assert [_, last, _] = progress.weeks(inputs(), 3)
  // Monday done, Wednesday missed, Thursday is a rest day. The Saturday jog was not planned, but it counts as training.
  assert last == Week(Date(2026, 9, 28), 2, 1, 1, 13_000.0, 8000.0, 2)
}

pub fn an_empty_week_is_all_zeros_test() {
  let assert [_, _, empty] = progress.weeks(inputs(), 3)
  assert empty == Week(Date(2026, 9, 21), 0, 0, 0, 0.0, 0.0, 0)
}

pub fn only_the_athletes_own_schedule_and_activities_count_test() {
  // Ben follows the same plan and ran 9999 m, which must not appear in Ana's weeks.
  let assert [_, last, _] = progress.weeks(inputs(), 3)
  assert last.activity_distance_m == 8000.0
  let ben = progress.weeks(Inputs(..inputs(), user_id: "ben"), 3)
  let assert [_, ben_last, _] = ben
  assert ben_last.activity_distance_m == 9999.0
  assert ben_last.done == 0
}

pub fn a_confirmed_match_counts_as_done_even_for_another_day_test() {
  // The coach sees what the athlete confirmed: Wednesday's tempo was the run made on Saturday.
  let linked =
    Inputs(..inputs(), matches: [
      Stored("m1", "ana", Match("x3", "wed1", "a1"), False, "T"),
    ])
  let assert [_, last, _] = progress.weeks(linked, 3)
  assert last.done == 2
  assert last.missed == 0
}

pub fn the_number_of_weeks_is_respected_test() {
  assert list.length(progress.weeks(inputs(), 1)) == 1
  assert list.length(progress.weeks(inputs(), 8)) == 8
  assert progress.weeks(inputs(), 0) == []
}

pub fn a_run_just_after_midnight_belongs_to_the_local_day_test() {
  // 22:30 UTC on Sunday 4 October is Monday 5 October in UTC+2: the next week.
  let late = run("late", "ana", "2026-10-04 22:30:00.000Z", 4000.0)
  let zurich = Inputs(..inputs(), activities: [late], offset_at: fn(_) { 120 })
  let assert [current, last, _] = progress.weeks(zurich, 3)
  assert current.activity_distance_m == 4000.0
  assert last.activity_distance_m == 0.0
  let utc = Inputs(..inputs(), activities: [late])
  let assert [current_utc, last_utc, _] = progress.weeks(utc, 3)
  assert current_utc.activity_distance_m == 0.0
  assert last_utc.activity_distance_m == 4000.0
}

fn ids(rows: List(activity_form.Row)) -> List(String) {
  list.map(rows, fn(r) { r.activity.id })
}

pub fn the_recent_activities_are_the_athletes_own_newest_first_test() {
  assert ids(progress.recent_activities(inputs(), 10)) == ["x2", "x3", "x1"]
  assert ids(progress.recent_activities(inputs(), 2)) == ["x2", "x3"]
  assert progress.recent_activities(Inputs(..inputs(), user_id: "nobody"), 10)
    == []
}
