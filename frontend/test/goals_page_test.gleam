import atlas/goal.{Goal}
import atlas/goals_page.{
  AddClicked, CancelClicked, Create, Delete, DeleteClicked, DeleteExpired,
  DistanceChanged, Edit, EditClicked, GoalsRead, Submitted, TimeChanged,
  UndoClicked,
}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element

fn update(model: goals_page.Model, msg: goals_page.Msg) {
  let #(next, _, actions) = goals_page.update(model, msg, "me")
  #(next, actions)
}

fn loaded(text: String) -> goals_page.Model {
  let assert Ok(value) = json.parse(text, decode.list(decode.dynamic))
  let #(model, _) = update(goals_page.new(), GoalsRead(Ok(value)))
  model
}

const saved =
  "[
  {\"id\":\"m\",\"owner\":\"me\",\"distance_m\":42195,\"time_s\":12600,\"deleted\":false,\"updated\":\"T1\"},
  {\"id\":\"t\",\"owner\":\"me\",\"distance_m\":10000,\"time_s\":2700,\"deleted\":false,\"updated\":\"T2\"},
  {\"id\":\"gone\",\"owner\":\"me\",\"distance_m\":5000,\"time_s\":1200,\"deleted\":true,\"updated\":\"T3\"},
  {\"id\":\"a\",\"owner\":\"ana\",\"distance_m\":5000,\"time_s\":1200,\"deleted\":false,\"updated\":\"T4\"},
  {\"id\":\"odd\",\"owner\":\"me\",\"distance_m\":0,\"time_s\":1200,\"deleted\":false,\"updated\":\"T5\"}
]"

pub fn the_page_lists_ones_own_goals_shortest_first_test() {
  let model = loaded(saved)
  assert goals_page.mine(model, "me")
    == [
      Goal("t", "me", 10_000.0, 2700, "T2"),
      Goal("m", "me", 42_195.0, 12_600, "T1"),
    ]
  let html = element.to_string(goals_page.view(model, "me"))
  assert string.contains(html, "10 km")
  assert string.contains(html, "45:00 · 4:30 /km")
  assert string.contains(html, "42.195 km")
  assert string.contains(html, "3:30:00 · 4:59 /km")
  assert !string.contains(html, ">5 km<")
}

pub fn without_goals_the_page_says_how_to_add_one_test() {
  let html = element.to_string(goals_page.view(loaded("[]"), "me"))
  assert string.contains(html, "No goals yet")
  assert string.contains(html, "Add goal")
}

pub fn adding_a_goal_creates_a_row_with_both_values_test() {
  let #(model, _) = update(loaded("[]"), AddClicked)
  assert model.mode == goals_page.Adding
  let #(model, _) = update(model, DistanceChanged("21.1"))
  let #(model, _) = update(model, TimeChanged("1:45"))
  let #(model, actions) = update(model, Submitted)
  assert model.mode == goals_page.Browsing
  let assert [Create(id, fields)] = actions
  assert id != ""
  assert fields == goal.fields("me", 21_100.0, 6300)
}

pub fn a_goal_without_a_time_is_refused_under_its_field_test() {
  let #(model, _) = update(loaded("[]"), AddClicked)
  let #(model, _) = update(model, DistanceChanged("10"))
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.mode == goals_page.Adding
  assert model.error_field == "time"
  let assert Some(_) = model.error
  let #(model, _) = update(model, TimeChanged("45"))
  assert model.error == None
}

pub fn editing_a_goal_fills_the_form_and_saves_with_its_base_test() {
  let #(model, _) = update(loaded(saved), EditClicked("m"))
  assert model.mode == goals_page.Editing("m")
  assert model.form == goal.Form("42.195", "3:30")
  let #(model, _) = update(model, TimeChanged("3:15"))
  let #(_, actions) = update(model, Submitted)
  assert actions == [Edit("m", goal.fields("me", 42_195.0, 11_700), "T1")]
}

pub fn someone_elses_goal_does_not_open_test() {
  let #(model, _) = update(loaded(saved), EditClicked("a"))
  assert model.mode == goals_page.Browsing
}

pub fn cancel_closes_the_form_without_writing_test() {
  let #(model, _) = update(loaded(saved), EditClicked("m"))
  let #(model, actions) = update(model, CancelClicked)
  assert model.mode == goals_page.Browsing
  assert actions == []
}

pub fn a_delete_waits_for_undo_then_is_written_test() {
  let #(model, _) = update(loaded(saved), EditClicked("t"))
  let #(model, actions) = update(model, DeleteClicked("t"))
  assert actions == []
  assert model.mode == goals_page.Browsing
  assert goals_page.mine(model, "me")
    == [Goal("m", "me", 42_195.0, 12_600, "T1")]
  let #(_, actions) = update(model, DeleteExpired(1))
  assert actions == [Delete("t", "T2")]
  let #(undone, _) = update(model, UndoClicked)
  assert list.length(goals_page.mine(undone, "me")) == 2
  let #(_, actions) = update(undone, DeleteExpired(1))
  assert actions == []
}
