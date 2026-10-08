import atlas/activity.{Activity}
import atlas/activity_form
import atlas/assignment_form
import atlas/date.{Date}
import atlas/matching.{Match, Stored}
import atlas/plan.{Assignment, Workout}
import atlas/today.{Done, Inputs, Missed, Planned, RestDay}
import gleam/list
import gleam/option.{None, Some}

// Plan starts Monday 2026-10-05, so day 0 is the 5th. "Today" is Wednesday the 7th (day 2).
const monday = Date(2026, 10, 5)

const wednesday = Date(2026, 10, 7)

fn assignment_row(
  id: String,
  athlete: String,
  plan_id: String,
  start: date.Date,
) -> assignment_form.Row {
  assignment_form.Row(Assignment(id, plan_id, athlete, start), athlete, "T")
}

fn workout(
  id: String,
  plan_id: String,
  day: Int,
  position: Int,
  kind: plan.Kind,
) -> plan.Workout {
  Workout(id, plan_id, day, position, id, kind, Some(8000.0), None)
}

fn activity_row(
  id: String,
  owner: String,
  started: String,
  sport: activity.Sport,
) -> activity_form.Row {
  activity_form.Row(
    Activity(id, activity.Manual, started, sport, 8000.0, 2500),
    owner,
    "",
    0.0,
    0,
    "T",
    "",
  )
}

fn stored(
  id: String,
  activity_id: String,
  workout_id: String,
  assignment_id: String,
) -> matching.Stored {
  Stored(
    id,
    "me",
    Match(activity_id, workout_id, assignment_id),
    False,
    "T-" <> id,
  )
}

fn inputs() -> today.Inputs {
  Inputs(
    user_id: "me",
    today: wednesday,
    assignments: [assignment_row("a1", "me", "p1", monday)],
    workouts: [
      workout("w0", "p1", 0, 0, plan.Easy),
      workout("w1", "p1", 1, 0, plan.Rest),
      workout("w2", "p1", 2, 0, plan.Tempo),
      workout("w3", "p1", 3, 0, plan.Easy),
      workout("w20", "p1", 20, 0, plan.Long),
    ],
    plans: [plan.new("p1", "me", "10k plan", "", plan.Private, "T")],
    activities: [],
    matches: [],
    offset_at: fn(_) { 0 },
  )
}

fn statuses(items: List(today.Item)) -> List(#(String, today.Status)) {
  list.map(items, fn(i) { #(i.scheduled.workout.id, i.status) })
}

pub fn the_window_is_a_week_either_side_of_today_test() {
  let found = today.items(inputs())
  // Days 0-3 are within reach; day 20 (the 25th) is not.
  assert list.map(found, fn(i) { i.scheduled.workout.id })
    == ["w0", "w1", "w2", "w3"]
}

pub fn without_activities_the_past_is_missed_and_today_and_later_are_planned_test() {
  assert statuses(today.items(inputs()))
    == [#("w0", Missed), #("w1", RestDay), #("w2", Planned), #("w3", Planned)]
}

pub fn the_plan_is_named_on_each_item_test() {
  let assert [first, ..] = today.items(inputs())
  assert first.plan_title == "10k plan"
  let unknown = today.items(Inputs(..inputs(), plans: []))
  let assert [also, ..] = unknown
  assert also.plan_title == "Plan"
}

pub fn a_matching_activity_is_proposed_as_done_test() {
  let with_run =
    Inputs(..inputs(), activities: [
      activity_row("x1", "me", "2026-10-07 06:00:00.000Z", activity.Run),
    ])
  let found = today.items(with_run)
  assert statuses(found)
    == [
      #("w0", Missed),
      #("w1", RestDay),
      #("w2", Done("x1", False)),
      #("w3", Planned),
    ]
  let assert Ok(done) =
    list.find(found, fn(i) { i.scheduled.workout.id == "w2" })
  assert done.stored == None
}

pub fn a_stored_match_wins_and_counts_as_confirmed_test() {
  let with_both =
    Inputs(
      ..inputs(),
      activities: [
        activity_row("x1", "me", "2026-10-07 06:00:00.000Z", activity.Run),
        activity_row("x2", "me", "2026-10-05 06:00:00.000Z", activity.Run),
      ],
      // The user said the run on the 5th was Wednesday's tempo workout.
      matches: [stored("m1", "x2", "w2", "a1")],
    )
  let found = today.items(with_both)
  let assert Ok(tempo) =
    list.find(found, fn(i) { i.scheduled.workout.id == "w2" })
  assert tempo.status == Done("x2", True)
  assert option.is_some(tempo.stored)
  // The run on the 7th is free again, and nothing else is planned for that day.
  let assert Ok(easy) =
    list.find(found, fn(i) { i.scheduled.workout.id == "w0" })
  assert easy.status == Missed
}

pub fn removed_or_dangling_stored_matches_are_ignored_test() {
  let removed = Stored("m1", "me", Match("x1", "w2", "a1"), True, "T")
  let dangling_activity = stored("m2", "gone", "w2", "a1")
  let dangling_workout = stored("m3", "x1", "no-such-workout", "a1")
  let with_run =
    Inputs(..inputs(), activities: [
      activity_row("x1", "me", "2026-10-07 06:00:00.000Z", activity.Run),
    ])
  let found =
    today.items(
      Inputs(..with_run, matches: [removed, dangling_activity, dangling_workout]),
    )
  // Falls back to the proposal: done, not confirmed.
  let assert Ok(tempo) =
    list.find(found, fn(i) { i.scheduled.workout.id == "w2" })
  assert tempo.status == Done("x1", False)
}

pub fn only_the_users_own_assignments_and_activities_count_test() {
  let other =
    Inputs(
      ..inputs(),
      assignments: [
        assignment_row("a1", "me", "p1", monday),
        assignment_row("a2", "ana", "p1", monday),
      ],
      activities: [
        activity_row("x1", "ana", "2026-10-07 06:00:00.000Z", activity.Run),
      ],
    )
  let found = today.items(other)
  // Ana's schedule is not on my screen, and her run does not complete my workout.
  assert list.length(found) == 4
  assert statuses(found)
    == [#("w0", Missed), #("w1", RestDay), #("w2", Planned), #("w3", Planned)]
}

pub fn two_plans_on_the_same_day_are_both_shown_test() {
  let two =
    Inputs(
      ..inputs(),
      assignments: [
        assignment_row("a1", "me", "p1", monday),
        assignment_row("a2", "me", "p2", monday),
      ],
      workouts: [
        workout("w2", "p1", 2, 0, plan.Tempo),
        workout("v2", "p2", 2, 0, plan.Strength),
      ],
      plans: [
        plan.new("p1", "me", "Running", "", plan.Private, "T"),
        plan.new("p2", "me", "Gym", "", plan.Private, "T"),
      ],
    )
  let found = today.items(two)
  assert list.map(found, fn(i) { i.plan_title }) == ["Gym", "Running"]
}

pub fn the_same_plan_followed_twice_is_two_items_test() {
  let twice =
    Inputs(
      ..inputs(),
      assignments: [
        assignment_row("a1", "me", "p1", monday),
        assignment_row("a2", "me", "p1", monday),
      ],
      workouts: [workout("w2", "p1", 2, 0, plan.Tempo)],
    )
  assert list.length(today.items(twice)) == 2
}

pub fn the_day_of_an_activity_follows_the_offset_that_applied_test() {
  // 22:30 UTC on the 6th is already the 7th in UTC+2.
  let late = activity_row("x1", "me", "2026-10-06 22:30:00.000Z", activity.Run)
  let in_utc = Inputs(..inputs(), activities: [late])
  assert statuses(today.items(in_utc))
    == [#("w0", Missed), #("w1", RestDay), #("w2", Planned), #("w3", Planned)]
  let in_zurich = Inputs(..in_utc, offset_at: fn(_) { 120 })
  assert statuses(today.items(in_zurich))
    == [
      #("w0", Missed),
      #("w1", RestDay),
      #("w2", Done("x1", False)),
      #("w3", Planned),
    ]
}

pub fn the_items_are_split_into_today_what_is_coming_and_what_passed_test() {
  let sections = today.sections(today.items(inputs()), wednesday)
  assert list.map(sections.today, fn(i) { i.scheduled.workout.id }) == ["w2"]
  assert list.map(sections.upcoming, fn(i) { i.scheduled.workout.id }) == ["w3"]
  // Latest first.
  assert list.map(sections.recent, fn(i) { i.scheduled.workout.id })
    == ["w1", "w0"]
}

pub fn candidates_are_the_users_activities_of_that_day_with_fitting_sports_first_test() {
  let activities = [
    activity_row("ride", "me", "2026-10-07 05:00:00.000Z", activity.Ride),
    activity_row("run", "me", "2026-10-07 18:00:00.000Z", activity.Run),
    activity_row("other-day", "me", "2026-10-06 18:00:00.000Z", activity.Run),
    activity_row("not-mine", "ana", "2026-10-07 18:00:00.000Z", activity.Run),
  ]
  let with_activities = Inputs(..inputs(), activities: activities)
  let assert Ok(tempo) =
    list.find(today.items(with_activities), fn(i) {
      i.scheduled.workout.id == "w2"
    })
  assert list.map(today.candidates(with_activities, tempo), fn(r) {
      r.activity.id
    })
    == ["run", "ride"]
}

pub fn an_activity_linked_to_another_workout_is_not_offered_test() {
  let activities = [
    activity_row("a", "me", "2026-10-07 05:00:00.000Z", activity.Run),
    activity_row("b", "me", "2026-10-07 18:00:00.000Z", activity.Run),
  ]
  let with_link =
    Inputs(..inputs(), activities: activities, matches: [
      stored("m1", "a", "w2", "a1"),
    ])
  // For Wednesday's own workout, its own link is still on offer; for Thursday's, nothing is on that day.
  let assert Ok(tempo) =
    list.find(today.items(with_link), fn(i) { i.scheduled.workout.id == "w2" })
  assert list.map(today.candidates(with_link, tempo), fn(r) { r.activity.id })
    == ["a", "b"]
  let two_workouts =
    Inputs(..with_link, workouts: [
      workout("w2", "p1", 2, 0, plan.Tempo),
      workout("w2b", "p1", 2, 1, plan.Strength),
    ])
  let assert Ok(second) =
    list.find(today.items(two_workouts), fn(i) {
      i.scheduled.workout.id == "w2b"
    })
  assert list.map(today.candidates(two_workouts, second), fn(r) {
      r.activity.id
    })
    == ["b"]
}

pub fn a_removed_match_row_is_found_so_it_can_be_reused_test() {
  let removed = Stored("m1", "me", Match("x1", "w2", "a1"), True, "T")
  assert today.row_for_activity([removed], "x1") == Some(removed)
  assert today.row_for_activity([removed], "other") == None
}

pub fn the_newest_stored_row_wins_when_two_claim_the_same_workout_test() {
  // Two devices linked different activities to the same workout; the later change is kept.
  let older =
    Stored(
      "m1",
      "me",
      Match("x1", "w2", "a1"),
      False,
      "2026-10-07 08:00:00.000Z",
    )
  let newer =
    Stored(
      "m2",
      "me",
      Match("x2", "w2", "a1"),
      False,
      "2026-10-07 09:00:00.000Z",
    )
  let both =
    Inputs(
      ..inputs(),
      activities: [
        activity_row("x1", "me", "2026-10-07 06:00:00.000Z", activity.Run),
        activity_row("x2", "me", "2026-10-07 07:00:00.000Z", activity.Run),
      ],
      matches: [older, newer],
    )
  let assert Ok(tempo) =
    list.find(today.items(both), fn(i) { i.scheduled.workout.id == "w2" })
  assert tempo.status == Done("x2", True)
}
