import atlas/activity.{Activity}
import atlas/activity_form
import atlas/assignment_form
import atlas/athletes_page
import atlas/date.{Date}
import atlas/grants.{Person}
import atlas/plan.{Assignment, Workout}
import atlas/today.{Inputs}
import gleam/option.{None, Some}
import gleam/string
import lustre/element

fn run(
  id: String,
  owner: String,
  started: String,
  meters: Float,
  name: String,
) -> activity_form.Row {
  activity_form.Row(
    Activity(id, activity.Strava, started, activity.Run, meters, 1800),
    owner,
    name,
    0.0,
    0,
    "T",
    "",
  )
}

fn inputs() -> today.Inputs {
  Inputs(
    user_id: "ana",
    today: Date(2026, 10, 7),
    assignments: [
      assignment_form.Row(
        Assignment("a1", "p1", "ana", Date(2026, 9, 28)),
        "me",
        "T",
      ),
      assignment_form.Row(
        Assignment("a2", "hidden", "ana", Date(2026, 8, 3)),
        "other-coach",
        "T",
      ),
    ],
    workouts: [
      Workout("w0", "p1", 0, 0, "Easy", plan.Easy, Some(5000.0), None),
      Workout("w2", "p1", 2, 0, "Tempo", plan.Tempo, Some(8000.0), None),
    ],
    plans: [plan.new("p1", "me", "Base block", "", plan.Private, "T")],
    activities: [
      run("x1", "ana", "2026-09-28 06:00:00.000Z", 5000.0, "Morning shake-out"),
      run("x2", "ana", "2026-10-03 06:00:00.000Z", 3000.0, ""),
      run("other", "ben", "2026-09-29 06:00:00.000Z", 9999.0, "Ben's run"),
    ],
    matches: [],
    offset_at: fn(_) { 0 },
  )
}

fn html_of(view: element.Element(a)) -> String {
  element.to_string(view)
}

pub fn the_list_links_to_each_athlete_test() {
  let html =
    html_of(
      athletes_page.view_list([Person("ana", "Ana"), Person("ben", "Ben")]),
    )
  assert string.contains(html, "href=\"/athletes/ana\"")
  assert string.contains(html, "Ana")
  assert string.contains(html, "href=\"/athletes/ben\"")
}

pub fn an_empty_list_explains_how_an_athlete_gives_access_test() {
  let html = html_of(athletes_page.view_list([]))
  assert string.contains(html, "Nobody has given you access yet")
  assert string.contains(html, "Settings, Coaches")
}

pub fn someone_who_is_not_an_athlete_is_refused_test() {
  let html = html_of(athletes_page.view_athlete(None, inputs()))
  assert string.contains(html, "You do not coach this person.")
  assert !string.contains(html, "Recent activities")
  assert string.contains(html, "All athletes")
}

pub fn the_athlete_page_says_whose_data_this_is_and_that_it_is_read_only_test() {
  let html =
    html_of(athletes_page.view_athlete(Some(Person("ana", "Ana")), inputs()))
  assert string.contains(html, "Ana")
  assert string.contains(
    html,
    "You can see this because Ana gave you access. It is read-only.",
  )
  assert !string.contains(html, "<button")
}

pub fn the_weeks_table_is_accessible_and_complete_test() {
  let html =
    html_of(athletes_page.view_athlete(Some(Person("ana", "Ana")), inputs()))
  assert string.contains(html, "<table")
  assert string.contains(
    html,
    "<caption>The last 6 weeks, newest first</caption>",
  )
  assert string.contains(html, "scope=\"col\"")
  assert string.contains(html, "scope=\"row\"")
  assert string.contains(html, "Week of")
  assert string.contains(html, "Planned km")
  assert string.contains(html, "Trained km")
  // The week of 28 September: two workouts planned (13.0 km), one done, one missed; 8.0 km trained.
  assert string.contains(html, "Mon 28 Sep 2026")
  assert string.contains(html, ">13.0<")
  assert string.contains(html, ">8.0<")
}

pub fn the_summary_counts_this_week_and_the_missed_workouts_test() {
  let html =
    html_of(athletes_page.view_athlete(Some(Person("ana", "Ana")), inputs()))
  assert string.contains(
    html,
    "This week: 0 of 0 workouts done. Missed in the last 6 weeks: 1.",
  )
}

pub fn the_plans_they_follow_name_readable_plans_and_hide_the_others_test() {
  let html =
    html_of(athletes_page.view_athlete(Some(Person("ana", "Ana")), inputs()))
  assert string.contains(html, "Base block")
  assert string.contains(html, "Starts Mon 28 Sep 2026")
  // A plan the coach cannot read shows its dates but not its name.
  assert string.contains(html, "A plan you cannot open")
  assert string.contains(html, "Starts Mon 3 Aug 2026")
}

pub fn recent_activities_are_the_athletes_own_newest_first_test() {
  let html =
    html_of(athletes_page.view_athlete(Some(Person("ana", "Ana")), inputs()))
  assert string.contains(html, "Recent activities")
  assert string.contains(html, "Morning shake-out")
  assert string.contains(html, "Sat 3 Oct 2026, 06:00")
  assert !string.contains(html, "Ben's run")
  let saturday = case string.split(html, "Sat 3 Oct 2026") {
    [before, ..] -> string.length(before)
    [] -> 0
  }
  let monday = case string.split(html, "Mon 28 Sep 2026, 06:00") {
    [before, ..] -> string.length(before)
    [] -> 0
  }
  assert saturday < monday
}

pub fn an_athlete_without_a_plan_or_activities_says_so_test() {
  let quiet = Inputs(..inputs(), assignments: [], activities: [])
  let html =
    html_of(athletes_page.view_athlete(Some(Person("ana", "Ana")), quiet))
  assert string.contains(html, "Not following a plan.")
  assert string.contains(html, "No activities yet.")
}

pub fn a_coach_sees_the_link_back_to_strava_too_test() {
  let strava_run =
    activity_form.Row(
      Activity(
        "x9",
        activity.Strava,
        "2026-10-04 06:00:00.000Z",
        activity.Run,
        4000.0,
        1200,
      ),
      "ana",
      "Sunday run",
      0.0,
      0,
      "T",
      "777888",
    )
  let with_link = Inputs(..inputs(), activities: [strava_run])
  let html =
    html_of(athletes_page.view_athlete(Some(Person("ana", "Ana")), with_link))
  assert string.contains(html, ">View on Strava<")
  assert string.contains(html, "https://www.strava.com/activities/777888")
}
