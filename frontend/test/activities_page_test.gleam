import atlas/activities_page.{
  ActivitiesRead, AddClicked, Adding, Browsing, Context, Create, DateChanged,
  Delete, DeleteClicked, DeleteConfirmed, DistanceChanged, DurationChanged, Edit,
  EditClicked, Editing, Model, NameChanged, SportChanged, Submitted, TimeChanged,
}
import atlas/activity.{Activity}
import atlas/activity_form.{type Row, Form, Row}
import atlas/date.{Date}
import atlas/outbox
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element

const today = Date(2026, 10, 6)

/// Swiss summer time all year: simple and enough to see conversions happen.
fn context() -> activities_page.Context {
  Context("me", today, fn(_, _, _) { 120 }, fn(_) { 120 })
}

fn row(
  id: String,
  owner: String,
  source: activity.Source,
  started: String,
  name: String,
) -> Row {
  Row(
    Activity(id, source, started, activity.Run, 8500.0, 2700),
    owner,
    name,
    120.0,
    152,
    "T-" <> id,
    "",
  )
}

fn with_rows(rows: List(Row)) -> activities_page.Model {
  Model(..activities_page.new(), rows: rows, loaded: True)
}

fn update(model: activities_page.Model, msg: activities_page.Msg) {
  let #(next, _, actions) = activities_page.update(model, msg, context())
  #(next, actions)
}

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

pub fn the_users_activities_are_listed_newest_first_without_deleted_or_foreign_ones_test() {
  let stored = [
    dynamic_of(
      "{\"id\":\"a\",\"owner\":\"me\",\"source\":\"manual\",\"started_at\":\"2026-10-01 05:00:00.000Z\",\"sport\":\"run\"}",
    ),
    dynamic_of(
      "{\"id\":\"b\",\"owner\":\"me\",\"source\":\"strava\",\"started_at\":\"2026-10-03 05:00:00.000Z\",\"sport\":\"run\"}",
    ),
    dynamic_of(
      "{\"id\":\"c\",\"owner\":\"athlete\",\"source\":\"strava\",\"started_at\":\"2026-10-05 05:00:00.000Z\",\"sport\":\"run\"}",
    ),
    dynamic_of(
      "{\"id\":\"gone\",\"owner\":\"me\",\"source\":\"manual\",\"started_at\":\"2026-10-04 05:00:00.000Z\",\"sport\":\"run\",\"deleted\":true}",
    ),
    dynamic_of(
      "{\"id\":\"odd\",\"owner\":\"me\",\"source\":\"manual\",\"started_at\":\"2026-10-04 05:00:00.000Z\",\"sport\":\"curling\"}",
    ),
  ]
  let #(model, _) = update(activities_page.new(), ActivitiesRead(Ok(stored)))
  assert model.loaded
  assert list.map(activities_page.mine(model, "me"), fn(r) { r.activity.id })
    == ["b", "a"]
}

pub fn only_manual_and_file_activities_of_your_own_can_be_changed_test() {
  assert activities_page.editable(
    row("a", "me", activity.Manual, "x", ""),
    "me",
  )
  assert activities_page.editable(row("a", "me", activity.Fit, "x", ""), "me")
  assert !activities_page.editable(
    row("a", "me", activity.Strava, "x", ""),
    "me",
  )
  assert !activities_page.editable(
    row("a", "me", activity.Garmin, "x", ""),
    "me",
  )
  assert !activities_page.editable(
    row("a", "other", activity.Manual, "x", ""),
    "me",
  )
}

pub fn adding_starts_today_in_the_morning_test() {
  let #(model, _) = update(activities_page.new(), AddClicked)
  assert model.mode == Adding
  assert model.form.date == "2026-10-06"
  assert model.form.time == "07:00"
}

pub fn adding_an_activity_converts_local_time_to_utc_test() {
  let #(model, _) = update(activities_page.new(), AddClicked)
  let #(model, _) = update(model, DateChanged("2026-10-05"))
  let #(model, _) = update(model, TimeChanged("07:30"))
  let #(model, _) = update(model, SportChanged("trail_run"))
  let #(model, _) = update(model, NameChanged("Morning loop"))
  let #(model, _) = update(model, DistanceChanged("8,5"))
  let #(model, _) = update(model, DurationChanged("1:05"))
  let #(model, actions) = update(model, Submitted)
  let assert [Create(id, fields)] = actions
  assert id != ""
  assert dict.get(fields, "owner") == Ok("\"me\"")
  assert dict.get(fields, "source") == Ok("\"manual\"")
  assert dict.get(fields, "started_at") == Ok("\"2026-10-05 05:30:00.000Z\"")
  assert dict.get(fields, "sport") == Ok("\"trail_run\"")
  assert dict.get(fields, "distance_m") == Ok("8500")
  assert dict.get(fields, "moving_time_s") == Ok("3900")
  assert model.mode == Browsing
}

pub fn an_invalid_activity_shows_its_error_and_saves_nothing_test() {
  let #(model, _) = update(activities_page.new(), AddClicked)
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.mode == Adding
  assert model.form.error == Some("Enter a distance or a time, or both.")
  let #(model, _) = update(model, DistanceChanged("5"))
  assert model.form.error == None
}

pub fn editing_shows_the_stored_values_in_local_time_test() {
  let model =
    with_rows([
      row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", "Morning run"),
    ])
  let #(model, _) = update(model, EditClicked("a"))
  assert model.mode == Editing("a")
  assert model.form
    == Form(
      "2026-10-01",
      "07:30",
      activity.Run,
      "Morning run",
      "8.5",
      "45",
      "120",
      "152",
      None,
    )
}

pub fn an_edit_sends_only_what_changed_with_the_local_base_test() {
  let model =
    with_rows([
      row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", "Morning run"),
    ])
  let #(model, _) = update(model, EditClicked("a"))
  let #(model, _) = update(model, NameChanged("Easy run"))
  let #(model, actions) = update(model, Submitted)
  assert actions
    == [
      Edit(
        "a",
        dict.from_list([outbox.field_string("name", "Easy run")]),
        "T-a",
      ),
    ]
  assert model.mode == Browsing
}

pub fn an_edit_without_changes_writes_nothing_test() {
  let model =
    with_rows([
      row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", "Morning run"),
    ])
  let #(model, _) = update(model, EditClicked("a"))
  let #(_, actions) = update(model, Submitted)
  assert actions == []
}

pub fn strava_and_foreign_activities_cannot_be_edited_or_deleted_test() {
  let model =
    with_rows([
      row("s", "me", activity.Strava, "2026-10-01 05:30:00.000Z", ""),
      row("f", "athlete", activity.Manual, "2026-10-01 05:30:00.000Z", ""),
    ])
  let #(edit, _) = update(model, EditClicked("s"))
  assert edit.mode == Browsing
  let #(edit, _) = update(model, EditClicked("f"))
  assert edit.mode == Browsing
  let #(_, actions) = update(model, DeleteConfirmed("s"))
  assert actions == []
  let #(_, actions) = update(model, DeleteConfirmed("f"))
  assert actions == []
}

pub fn deleting_needs_a_second_click_test() {
  let model =
    with_rows([row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", "")])
  let #(asked, actions) = update(model, DeleteClicked("a"))
  assert asked.confirming == Some("a")
  assert actions == []
  let #(done, actions) = update(asked, DeleteConfirmed("a"))
  assert actions == [Delete("a", "T-a")]
  assert done.confirming == None
}

pub fn an_activity_removed_elsewhere_ends_its_edit_test() {
  let editing =
    Model(
      ..with_rows([
        row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", ""),
      ]),
      mode: Editing("a"),
    )
  let #(model, _) = update(editing, ActivitiesRead(Ok([])))
  assert model.mode == Browsing
}

// What is on the screen ---------------------------------------------------------------------------

fn html_of(model: activities_page.Model) -> String {
  element.to_string(activities_page.view(model, context()))
}

pub fn a_list_entry_shows_local_time_figures_and_pace_test() {
  let html =
    html_of(
      with_rows([
        row(
          "a",
          "me",
          activity.Manual,
          "2026-10-01 05:30:00.000Z",
          "Morning run",
        ),
      ]),
    )
  assert string.contains(html, "Morning run")
  assert string.contains(html, "Thu 1 Oct 2026, 07:30")
  assert string.contains(html, "8.50 km")
  assert string.contains(html, "45:00")
  assert string.contains(html, "5:18 /km")
  assert string.contains(html, "120 m")
  assert string.contains(html, "152 bpm")
  assert string.contains(html, "Added by hand")
}

pub fn an_unnamed_activity_is_called_by_its_sport_test() {
  let html =
    html_of(
      with_rows([
        row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", ""),
      ]),
    )
  assert string.contains(html, ">Run<")
}

pub fn strava_entries_have_no_buttons_and_say_where_they_come_from_test() {
  let html =
    html_of(
      with_rows([
        row("s", "me", activity.Strava, "2026-10-01 05:30:00.000Z", "Lunch run"),
      ]),
    )
  assert string.contains(html, "Strava")
  assert !string.contains(html, ">Edit<")
  assert !string.contains(html, ">Delete<")
}

pub fn an_unsynced_entry_is_marked_test() {
  let unsynced =
    Row(
      ..row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", ""),
      updated: "",
    )
  assert string.contains(html_of(with_rows([unsynced])), "Not synced yet")
}

pub fn only_the_users_own_activities_are_shown_test() {
  let html =
    html_of(
      with_rows([
        row(
          "f",
          "athlete",
          activity.Strava,
          "2026-10-01 05:30:00.000Z",
          "Athlete's run",
        ),
      ]),
    )
  assert !string.contains(html, "Athlete's run")
  assert string.contains(html, "No activities yet")
}

pub fn the_list_says_loading_before_the_first_read_test() {
  assert string.contains(html_of(activities_page.new()), "Loading")
}

pub fn the_form_is_labelled_and_shows_errors_test() {
  let model =
    Model(
      ..with_rows([]),
      mode: Adding,
      form: Form(
        "2026-10-06",
        "07:00",
        activity.Run,
        "",
        "",
        "",
        "",
        "",
        Some("Enter a distance or a time, or both."),
      ),
    )
  let html = html_of(model)
  assert string.contains(html, "for=\"activity-date\"")
  assert string.contains(html, "type=\"date\"")
  assert string.contains(html, "type=\"time\"")
  assert string.contains(html, "for=\"activity-distance\"")
  assert string.contains(html, "Trail run")
  assert string.contains(html, "role=\"alert\"")
  assert string.contains(html, "Enter a distance or a time, or both.")
}

pub fn the_delete_question_has_a_way_out_test() {
  let model =
    Model(
      ..with_rows([
        row("a", "me", activity.Manual, "2026-10-01 05:30:00.000Z", ""),
      ]),
      confirming: Some("a"),
    )
  let html = html_of(model)
  assert string.contains(html, "Delete this activity?")
  assert string.contains(html, "Yes, delete it")
  assert string.contains(html, "Keep it")
}

fn from_strava(external_id: String) -> activity_form.Row {
  Row(
    ..row("s", "me", activity.Strava, "2026-10-01 05:30:00.000Z", "Lunch run"),
    external_id: external_id,
  )
}

pub fn a_strava_activity_says_view_on_strava_and_links_to_it_test() {
  let html = html_of(with_rows([from_strava("5551234")]))
  assert string.contains(html, ">View on Strava<")
  assert string.contains(
    html,
    "href=\"https://www.strava.com/activities/5551234\"",
  )
  assert string.contains(html, "target=\"_blank\"")
  assert string.contains(html, "rel=\"noopener noreferrer\"")
  assert string.contains(html, "strava-link")
}

pub fn activities_from_elsewhere_have_no_strava_link_test() {
  let manual =
    html_of(
      with_rows([
        Row(
          ..row("m", "me", activity.Manual, "2026-10-01 05:30:00.000Z", ""),
          external_id: "5551234",
        ),
      ]),
    )
  assert !string.contains(manual, "View on Strava")
  let without_id = html_of(with_rows([from_strava("")]))
  assert !string.contains(without_id, "View on Strava")
}
