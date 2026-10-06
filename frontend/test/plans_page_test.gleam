import atlas/outbox
import atlas/plan.{type Plan, Plan}
import atlas/plan_form.{Form}
import atlas/plans_page.{
  Browsing, Create, Creating, Delete, DeleteClicked, DeleteConfirmed, Edit,
  EditClicked, Editing, Model, NewClicked, PlansRead, Submitted, TitleChanged,
}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn mine(id: String, title: String) -> Plan {
  Plan(id, "u1", title, "", plan.Private, "T-" <> id)
}

fn others(id: String, title: String) -> Plan {
  Plan(id, "u2", title, "", plan.Public, "T-" <> id)
}

fn with_plans(plans: List(Plan)) -> plans_page.Model {
  Model(..plans_page.new(), plans: plans, loaded: True)
}

fn update(model: plans_page.Model, msg: plans_page.Msg) {
  let #(next, _, actions) = plans_page.update(model, msg, "u1")
  #(next, actions)
}

pub fn the_stored_records_become_a_sorted_list_without_deleted_ones_test() {
  let stored = [
    dynamic_of("{\"id\":\"b\",\"title\":\"banana\",\"owner\":\"u1\"}"),
    dynamic_of("{\"id\":\"gone\",\"title\":\"Deleted\",\"deleted\":true}"),
    dynamic_of("{\"id\":\"a\",\"title\":\"Apple\",\"owner\":\"u1\"}"),
    dynamic_of("{\"id\":\"broken\"}"),
    dynamic_of("{\"id\":\"c\",\"title\":\"cherry\",\"owner\":\"u1\"}"),
  ]
  let #(model, _) = update(plans_page.new(), PlansRead(Ok(stored)))
  assert model.loaded
  assert list.map(model.plans, fn(p) { p.id }) == ["a", "b", "c"]
}

pub fn equal_titles_keep_a_stable_order_test() {
  let stored = [
    dynamic_of("{\"id\":\"z\",\"title\":\"Same\"}"),
    dynamic_of("{\"id\":\"y\",\"title\":\"same\"}"),
  ]
  let #(model, _) = update(plans_page.new(), PlansRead(Ok(stored)))
  assert list.map(model.plans, fn(p) { p.id }) == ["y", "z"]
}

pub fn a_failed_read_keeps_what_is_on_screen_test() {
  let before = with_plans([mine("a", "A")])
  let #(model, actions) = update(before, PlansRead(Error(Nil)))
  assert model == before
  assert actions == []
}

pub fn creating_a_plan_asks_the_app_to_save_it_test() {
  let #(model, _) = update(plans_page.new(), NewClicked)
  assert model.mode == Creating
  let #(model, _) = update(model, TitleChanged("  10k plan "))
  let #(model, actions) = update(model, Submitted)
  let assert [Create(id, fields)] = actions
  assert id != ""
  assert dict.get(fields, "title") == Ok("\"10k plan\"")
  assert dict.get(fields, "owner") == Ok("\"u1\"")
  assert model.mode == Browsing
  assert model.form == plan_form.empty()
}

pub fn an_empty_title_shows_an_error_and_saves_nothing_test() {
  let #(model, _) = update(plans_page.new(), NewClicked)
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.mode == Creating
  assert model.form.error == Some("Give the plan a title.")
  // Typing clears the error again.
  let #(model, _) = update(model, TitleChanged("x"))
  assert model.form.error == None
}

pub fn editing_sends_only_the_changed_fields_with_the_local_base_test() {
  let model = with_plans([mine("a", "Old title")])
  let #(model, _) = update(model, EditClicked("a"))
  assert model.mode == Editing("a")
  assert model.form.title == "Old title"
  let #(model, _) = update(model, TitleChanged("New title"))
  let #(model, actions) = update(model, Submitted)
  assert actions
    == [
      Edit(
        "a",
        dict.from_list([outbox.field_string("title", "New title")]),
        "T-a",
      ),
    ]
  assert model.mode == Browsing
}

pub fn an_edit_without_changes_writes_nothing_test() {
  let model = with_plans([mine("a", "Same")])
  let #(model, _) = update(model, EditClicked("a"))
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.mode == Browsing
}

pub fn plans_of_other_people_cannot_be_edited_or_deleted_test() {
  let model = with_plans([others("o", "Shared")])
  let #(edit, actions) = update(model, EditClicked("o"))
  assert edit.mode == Browsing
  assert actions == []
  let #(_, actions) = update(model, DeleteConfirmed("o"))
  assert actions == []
}

pub fn deleting_needs_a_second_click_test() {
  let model = with_plans([mine("a", "A")])
  let #(asked, actions) = update(model, DeleteClicked)
  assert asked.confirming_delete
  assert actions == []
  let #(done, actions) = update(asked, DeleteConfirmed("a"))
  assert actions == [Delete("a", "T-a")]
  assert !done.confirming_delete
}

pub fn cancelling_leaves_the_form_and_the_question_test() {
  let model =
    Model(
      ..with_plans([mine("a", "A")]),
      mode: Editing("a"),
      confirming_delete: True,
    )
  let #(next, _) = update(model, plans_page.CancelClicked)
  assert next.mode == Browsing
  assert !next.confirming_delete
}

pub fn a_plan_deleted_elsewhere_ends_an_edit_of_it_test() {
  let editing = Model(..with_plans([mine("a", "A")]), mode: Editing("a"))
  let #(model, _) = update(editing, PlansRead(Ok([])))
  assert model.mode == Browsing
}

pub fn snippets_are_one_short_line_test() {
  assert plans_page.snippet("First line\nsecond line") == "First line"
  assert plans_page.snippet("") == ""
  assert string.length(plans_page.snippet(string.repeat("x", 300))) == 120
  assert plans_page.snippet(string.repeat("x", 120)) == string.repeat("x", 120)
}

// What is on the screen ---------------------------------------------------------------------------

fn html_of(view: element.Element(plans_page.Msg)) -> String {
  element.to_string(view)
}

pub fn the_list_shows_own_plans_and_shared_ones_apart_test() {
  let html =
    html_of(plans_page.view_list(
      with_plans([mine("a", "My plan"), others("o", "Coach plan")]),
      "u1",
    ))
  assert string.contains(html, "href=\"/plans/a\"")
  assert string.contains(html, "My plan")
  assert string.contains(html, "Shared with you")
  assert string.contains(html, "Coach plan")
  assert string.contains(html, "Public")
  assert string.contains(html, "New plan")
}

pub fn an_empty_list_says_what_to_do_test() {
  let html = html_of(plans_page.view_list(with_plans([]), "u1"))
  assert string.contains(html, "You have no plans yet")
  assert !string.contains(html, "Shared with you")
}

pub fn the_list_says_loading_before_the_first_read_test() {
  let html = html_of(plans_page.view_list(plans_page.new(), "u1"))
  assert string.contains(html, "Loading")
  assert !string.contains(html, "You have no plans yet")
}

pub fn an_unsynced_plan_is_marked_test() {
  let unsynced = Plan("n", "u1", "New one", "", plan.Private, "")
  let html = html_of(plans_page.view_list(with_plans([unsynced]), "u1"))
  assert string.contains(html, "Not synced yet")
}

pub fn the_form_is_accessible_and_shows_errors_test() {
  let model =
    Model(
      ..with_plans([]),
      mode: Creating,
      form: Form("", "", plan.Private, Some("Give the plan a title.")),
    )
  let html = html_of(plans_page.view_list(model, "u1"))
  assert string.contains(html, "for=\"plan-title\"")
  assert string.contains(html, "id=\"plan-title\"")
  assert string.contains(html, "maxlength=\"200\"")
  assert string.contains(html, "role=\"alert\"")
  assert string.contains(html, "Give the plan a title.")
}

pub fn the_detail_of_an_own_plan_offers_edit_and_delete_test() {
  let html =
    html_of(plans_page.view_detail(
      with_plans([mine("a", "My plan")]),
      "a",
      "u1",
    ))
  assert string.contains(html, "My plan")
  assert string.contains(html, ">Edit<")
  assert string.contains(html, ">Delete<")
}

pub fn the_detail_of_a_shared_plan_is_read_only_test() {
  let html =
    html_of(plans_page.view_detail(
      with_plans([others("o", "Coach plan")]),
      "o",
      "u1",
    ))
  assert string.contains(html, "Coach plan")
  assert string.contains(html, "Only its owner can change it")
  assert !string.contains(html, ">Edit<")
  assert !string.contains(html, ">Delete<")
}

pub fn a_missing_plan_is_explained_test() {
  let html = html_of(plans_page.view_detail(with_plans([]), "nope", "u1"))
  assert string.contains(html, "not on this device")
  assert string.contains(html, "All plans")
}

pub fn the_delete_question_has_a_clear_way_out_test() {
  let model = Model(..with_plans([mine("a", "A")]), confirming_delete: True)
  let html = html_of(plans_page.view_detail(model, "a", "u1"))
  assert string.contains(html, "Delete this plan?")
  assert string.contains(html, "Yes, delete it")
  assert string.contains(html, "Keep it")
}
