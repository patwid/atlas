import atlas/activity.{Activity}
import atlas/activity_form
import atlas/assignment_form
import atlas/date.{Date}
import atlas/matching.{Match, Stored}
import atlas/outbox
import atlas/plan.{Assignment, Workout}
import atlas/today.{Inputs}
import atlas/today_page.{
  CancelClicked, ChooseClicked, ConfirmClicked, Create, Delete, Edit, Key,
  MatchesRead, Model, PickClicked, UnlinkClicked, UnlinkNoticeExpired,
  UnlinkUndone,
}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import lustre/element

const monday = Date(2026, 10, 5)

const wednesday = Date(2026, 10, 7)

fn activity_row(
  id: String,
  owner: String,
  started: String,
  sport: activity.Sport,
) -> activity_form.Row {
  activity_form.Row(
    Activity(id, activity.Manual, started, sport, 8000.0, 2700),
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
  deleted: Bool,
) -> matching.Stored {
  Stored(id, "me", Match(activity_id, workout_id, "a1"), deleted, "T-" <> id)
}

fn inputs(matches: List(matching.Stored)) -> today.Inputs {
  Inputs(
    user_id: "me",
    today: wednesday,
    assignments: [
      assignment_form.Row(Assignment("a1", "p1", "me", monday), "me", "T"),
    ],
    workouts: [
      Workout("w1", "p1", 1, 0, "Tuesday easy", plan.Easy, Some(8000.0), None),
      Workout(
        "w2",
        "p1",
        2,
        0,
        "Wednesday tempo",
        plan.Tempo,
        Some(8000.0),
        Some(2700),
      ),
      Workout("w3", "p1", 3, 0, "Thursday rest", plan.Rest, None, None),
    ],
    plans: [plan.new("p1", "me", "10k plan", "", plan.Private, "T")],
    activities: [
      activity_row("x1", "me", "2026-10-07 06:00:00.000Z", activity.Run),
      activity_row("x2", "me", "2026-10-07 18:00:00.000Z", activity.Run),
      activity_row("x3", "me", "2026-10-06 06:00:00.000Z", activity.Run),
      activity_row("foreign", "ana", "2026-10-07 06:00:00.000Z", activity.Run),
    ],
    matches: matches,
    offset_at: fn(_) { 0 },
  )
}

fn update(model: today_page.Model, msg: today_page.Msg, i: today.Inputs) {
  let #(next, _, actions) = today_page.update(model, msg, i)
  #(next, actions)
}

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

const wednesday_key = Key("a1", "w2")

pub fn stored_matches_are_read_with_removed_ones_test() {
  let stored_records = [
    dynamic_of(
      "{\"id\":\"m1\",\"owner\":\"me\",\"activity\":\"x1\",\"assignment\":\"a1\",\"workout\":\"w2\"}",
    ),
    dynamic_of(
      "{\"id\":\"m2\",\"owner\":\"me\",\"activity\":\"x2\",\"assignment\":\"a1\",\"workout\":\"w1\",\"deleted\":true}",
    ),
    dynamic_of("{\"id\":\"broken\"}"),
  ]
  let #(model, _) =
    update(today_page.new(), MatchesRead(Ok(stored_records)), inputs([]))
  assert model.loaded
  assert model.matches |> list_length == 2
}

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

pub fn confirming_a_suggestion_creates_a_stored_match_test() {
  let #(_, actions) =
    update(today_page.new(), ConfirmClicked(wednesday_key, "x1"), inputs([]))
  let assert [Create(id, fields)] = actions
  assert id != ""
  assert fields
    == dict.from_list([
      outbox.field_string("owner", "me"),
      outbox.field_string("activity", "x1"),
      outbox.field_string("assignment", "a1"),
      outbox.field_string("workout", "w2"),
    ])
}

pub fn picking_an_activity_closes_the_list_test() {
  let choosing = Model(..today_page.new(), choosing: Some(wednesday_key))
  let #(model, actions) =
    update(choosing, PickClicked(wednesday_key, "x2"), inputs([]))
  assert model.choosing == None
  let assert [Create(_, fields)] = actions
  assert dict.get(fields, "activity") == Ok("\"x2\"")
}

pub fn linking_an_activity_whose_match_was_removed_reuses_its_row_test() {
  // One row per activity: a new row would be refused by the server, so the old one is changed.
  let removed = stored("m1", "x3", "w1", True)
  let #(_, actions) =
    update(
      today_page.new(),
      PickClicked(wednesday_key, "x3"),
      inputs([removed]),
    )
  assert actions
    == [
      Edit(
        "m1",
        dict.from_list([
          outbox.field_bool("deleted", False),
          outbox.field_string("assignment", "a1"),
          outbox.field_string("workout", "w2"),
        ]),
        "T-m1",
      ),
    ]
}

pub fn linking_an_activity_that_is_already_linked_here_does_nothing_test() {
  let live = stored("m1", "x1", "w2", False)
  let #(_, actions) =
    update(today_page.new(), PickClicked(wednesday_key, "x1"), inputs([live]))
  assert actions == []
}

pub fn moving_an_activity_to_another_workout_edits_its_row_test() {
  let live = stored("m1", "x1", "w1", False)
  let #(_, actions) =
    update(today_page.new(), PickClicked(wednesday_key, "x1"), inputs([live]))
  let assert [Edit("m1", fields, "T-m1")] = actions
  assert dict.get(fields, "workout") == Ok("\"w2\"")
}

pub fn choosing_another_activity_removes_the_old_link_first_test() {
  let live = stored("m1", "x1", "w2", False)
  let #(_, actions) =
    update(today_page.new(), PickClicked(wednesday_key, "x2"), inputs([live]))
  let assert [Delete("m1", "T-m1"), Create(_, fields)] = actions
  assert dict.get(fields, "activity") == Ok("\"x2\"")
}

pub fn only_known_workouts_and_own_activities_can_be_linked_test() {
  let none = fn(msg) { update(today_page.new(), msg, inputs([])).1 }
  assert none(PickClicked(Key("a1", "no-such-workout"), "x1")) == []
  assert none(PickClicked(Key("other-assignment", "w2"), "x1")) == []
  assert none(PickClicked(wednesday_key, "foreign")) == []
  assert none(PickClicked(wednesday_key, "no-such-activity")) == []
}

pub fn unlinking_acts_at_once_and_offers_undo_test() {
  let live = stored("m1", "x1", "w2", False)
  let i = inputs([live])
  let #(unlinked, actions) =
    update(today_page.new(), UnlinkClicked(wednesday_key), i)
  assert actions == [Delete("m1", "T-m1")]
  assert string.contains(html_of(unlinked, i), "Activity unlinked")
  assert string.contains(html_of(unlinked, i), ">Undo<")
  // The snackbar's own timer closes it; an older one does not.
  let #(still, _) = update(unlinked, UnlinkNoticeExpired(0), i)
  assert still.unlinked == unlinked.unlinked
  let #(closed, _) = update(unlinked, UnlinkNoticeExpired(1), i)
  assert closed.unlinked == None
}

pub fn undo_links_the_same_activity_again_test() {
  let removed = stored("m1", "x1", "w2", True)
  let i = inputs([removed])
  let unlinked =
    Model(..today_page.new(), unlinked: Some(#(1, wednesday_key, "x1")))
  let #(next, actions) = update(unlinked, UnlinkUndone, i)
  assert next.unlinked == None
  let assert [Edit("m1", _, _)] = actions
}

pub fn unlinking_something_not_stored_does_nothing_test() {
  let #(_, actions) =
    update(today_page.new(), UnlinkClicked(wednesday_key), inputs([]))
  assert actions == []
}

pub fn the_list_of_activities_opens_and_cancels_test() {
  let #(open, _) =
    update(today_page.new(), ChooseClicked(wednesday_key), inputs([]))
  assert open.choosing == Some(wednesday_key)
  let #(closed, _) = update(open, CancelClicked, inputs([]))
  assert closed.choosing == None
}

// What is on the screen ---------------------------------------------------------------------------

fn html_of(model: today_page.Model, i: today.Inputs) -> String {
  element.to_string(today_page.view(model, i))
}

pub fn without_a_plan_the_screen_points_to_the_plans_test() {
  let html = html_of(today_page.new(), Inputs(..inputs([]), assignments: []))
  assert string.contains(html, "You are not following a plan yet")
  assert string.contains(html, "href=\"/plans\"")
}

pub fn the_day_and_its_sections_are_shown_test() {
  let html = html_of(today_page.new(), inputs([]))
  assert string.contains(html, "Wed 7 Oct 2026")
  assert string.contains(html, "Today")
  assert string.contains(html, "Wednesday tempo")
  assert string.contains(html, "Tempo run")
  assert string.contains(html, "10k plan")
  assert string.contains(html, "Planned: 8 km · 45:00")
  assert string.contains(html, "Coming up")
  assert string.contains(html, "Thursday rest")
  assert string.contains(html, "Rest day")
  assert string.contains(html, "Last 7 days")
}

pub fn a_suggested_match_asks_for_confirmation_test() {
  let html = html_of(today_page.new(), inputs([]))
  // The 6th's run is not on a planned day of this plan except Tuesday: it is suggested there.
  assert string.contains(html, "Looks done</span>")
  assert string.contains(html, "06:00 · Run · 8.00 km · 45:00")
  assert string.contains(html, ">Confirm<")
  assert string.contains(html, "Choose another")
}

pub fn a_confirmed_match_can_be_changed_or_unlinked_test() {
  let html =
    html_of(today_page.new(), inputs([stored("m1", "x1", "w2", False)]))
  assert string.contains(html, ">Done</span>")
  assert string.contains(html, "06:00 · Run · 8.00 km · 45:00")
  assert string.contains(html, ">Change<")
  assert string.contains(html, ">Unlink<")
}

pub fn missed_workouts_say_so_and_offer_a_link_test() {
  let no_runs = Inputs(..inputs([]), activities: [])
  let html = html_of(today_page.new(), no_runs)
  assert string.contains(html, "Missed")
  assert string.contains(html, "To do")
  assert string.contains(html, "Link an activity")
}

pub fn workouts_still_to_come_offer_no_link_test() {
  let tomorrow_only = Inputs(..inputs([]), today: monday, activities: [])
  let html = html_of(today_page.new(), tomorrow_only)
  let assert [_, coming_up] = string.split(html, "Coming up")
  assert string.contains(coming_up, "To do")
  assert !string.contains(coming_up, "Link an activity")
}

pub fn the_activity_list_offers_that_days_activities_test() {
  let model = Model(..today_page.new(), choosing: Some(wednesday_key))
  let html = html_of(model, inputs([]))
  assert string.contains(html, "Which activity was it?")
  assert string.contains(html, "class=\"choice-row\"")
  assert string.contains(html, "data-open=\"true\"")
  assert string.contains(html, "18:00 · Run")
}

pub fn an_empty_activity_list_says_what_to_do_test() {
  let model = Model(..today_page.new(), choosing: Some(wednesday_key))
  let html = html_of(model, Inputs(..inputs([]), activities: []))
  assert string.contains(
    html,
    "You have no activity on Wed 7 Oct 2026. Add one in Activities first.",
  )
}
