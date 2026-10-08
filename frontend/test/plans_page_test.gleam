import atlas/outbox
import atlas/plan.{type Plan}
import atlas/plan_form.{Form}
import atlas/plans_page.{
  BaseWeeksChanged, Browsing, CompetitionWeeksChanged, Create, Creating, Delete,
  DeleteClicked, DeleteConfirmed, Edit, EditClicked, Editing, GoalChanged, Model,
  NewClicked, PlansRead, PreCompetitionWeeksChanged, Submitted, TitleChanged,
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
  plan.Plan(
    ..plan.new(id, "u1", title, "", plan.Private, "T-" <> id),
    phases: plan.default_phases,
  )
}

fn others(id: String, title: String) -> Plan {
  plan.new(id, "u2", title, "", plan.Public, "T-" <> id)
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

pub fn a_new_plan_carries_its_phases_and_goal_test() {
  let #(model, _) = update(plans_page.new(), NewClicked)
  let #(model, _) = update(model, TitleChanged("Marathon"))
  let #(model, _) = update(model, BaseWeeksChanged("8"))
  let #(model, _) = update(model, PreCompetitionWeeksChanged("0"))
  let #(model, _) = update(model, CompetitionWeeksChanged("3"))
  let #(model, _) = update(model, GoalChanged("55"))
  let #(_, actions) = update(model, Submitted)
  let assert [Create(_, fields)] = actions
  assert dict.get(fields, "base_weeks") == Ok("8")
  assert dict.get(fields, "pre_competition_weeks") == Ok("0")
  assert dict.get(fields, "competition_weeks") == Ok("3")
  assert dict.get(fields, "weekly_distance_m")
    == Ok(outbox.field_float("x", 55_000.0).1)
}

pub fn invalid_phases_keep_the_form_open_with_a_message_test() {
  let #(model, _) = update(plans_page.new(), NewClicked)
  let #(model, _) = update(model, TitleChanged("Marathon"))
  let #(model, _) = update(model, BaseWeeksChanged("0"))
  let #(model, _) = update(model, PreCompetitionWeeksChanged("0"))
  let #(model, _) = update(model, CompetitionWeeksChanged("0"))
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.form.error == Some("The plan needs at least one week.")
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

pub fn editing_a_plan_without_phases_gives_it_the_default_ones_test() {
  let old = plan.new("o", "u1", "Old", "", plan.Private, "T-o")
  let model = with_plans([old])
  let #(model, _, _) = plans_page.update(model, EditClicked("o"), "u1")
  let #(_, _, actions) = plans_page.update(model, Submitted, "u1")
  assert actions
    == [
      Edit(
        "o",
        dict.from_list([
          outbox.field_int("base_weeks", 4),
          outbox.field_int("pre_competition_weeks", 4),
          outbox.field_int("competition_weeks", 4),
        ]),
        "T-o",
      ),
    ]
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
  let unsynced = plan.new("n", "u1", "New one", "", plan.Private, "")
  let html = html_of(plans_page.view_list(with_plans([unsynced]), "u1"))
  assert string.contains(html, "Not synced yet")
}

pub fn the_form_is_accessible_and_shows_errors_test() {
  let model =
    Model(
      ..with_plans([]),
      mode: Creating,
      form: Form(
        "",
        "",
        plan.Private,
        plan_form.default_settings(),
        Some("Give the plan a title."),
      ),
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
  // The plan's name is the app bar's title now (ADR 0055), see atlas_test.
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
  // The plan's name is the app bar's title now (ADR 0055), see atlas_test.
  assert string.contains(html, "Only its owner can change it")
  assert !string.contains(html, ">Edit<")
  assert !string.contains(html, ">Delete<")
}

pub fn a_missing_plan_is_explained_test() {
  let html = html_of(plans_page.view_detail(with_plans([]), "nope", "u1"))
  assert string.contains(html, "not on this device")
}

pub fn the_delete_question_has_a_clear_way_out_test() {
  let model = Model(..with_plans([mine("a", "A")]), confirming_delete: True)
  let html = html_of(plans_page.view_detail(model, "a", "u1"))
  assert string.contains(html, "Delete plan?")
  assert string.contains(html, ">Delete<")
  assert string.contains(html, ">Cancel<")
}

// Copying -----------------------------------------------------------------------------------------

pub fn copying_asks_the_app_and_blocks_a_second_click_test() {
  let model = with_plans([others("o", "Coach plan")])
  let #(copying, actions) = update(model, plans_page.CopyClicked("o"))
  assert actions == [plans_page.Copy("o")]
  assert copying.copy == plans_page.Copying("o")
  // A double click does not start a second copy.
  let #(still, actions) = update(copying, plans_page.CopyClicked("o"))
  assert actions == []
  assert still == copying
}

pub fn a_finished_copy_offers_the_new_plan_and_blocks_another_click_test() {
  let copying =
    Model(
      ..with_plans([others("o", "Coach plan")]),
      copy: plans_page.Copying("o"),
    )
  let #(done, _) = update(copying, plans_page.CopyMade("o", "new1"))
  assert done.copy == plans_page.Copied("o", "new1")
  let #(same, actions) = update(done, plans_page.CopyClicked("o"))
  assert actions == []
  assert same == done
  // "Copy again" lifts the block.
  let #(again, _) = update(done, plans_page.CopyAgainClicked)
  assert again.copy == plans_page.NoCopy
  let #(second, actions) = update(again, plans_page.CopyClicked("o"))
  assert actions == [plans_page.Copy("o")]
  assert second.copy == plans_page.Copying("o")
}

pub fn a_plan_not_on_the_device_cannot_be_copied_test() {
  let #(model, actions) = update(with_plans([]), plans_page.CopyClicked("nope"))
  assert actions == []
  assert model.copy == plans_page.NoCopy
}

pub fn a_failed_copy_says_why_and_can_be_retried_test() {
  let copying =
    Model(..with_plans([mine("a", "A")]), copy: plans_page.Copying("a"))
  let #(failed, _) =
    update(copying, plans_page.CopyFailed("a", "Try again in a moment."))
  assert failed.copy == plans_page.CopyProblem("a", "Try again in a moment.")
  let html = html_of(plans_page.view_detail(failed, "a", "u1"))
  assert string.contains(html, "Try again in a moment.")
  assert string.contains(html, "role=\"alert\"")
  let #(retry, _) = update(failed, plans_page.CopyAgainClicked)
  assert retry.copy == plans_page.NoCopy
}

pub fn every_plan_on_screen_offers_a_copy_test() {
  let own =
    html_of(plans_page.view_detail(with_plans([mine("a", "Mine")]), "a", "u1"))
  assert string.contains(own, "Copy to my plans")
  let shared =
    html_of(plans_page.view_detail(
      with_plans([others("o", "Theirs")]),
      "o",
      "u1",
    ))
  assert string.contains(shared, "Copy to my plans")
  assert string.contains(shared, "Copy it to make a version of your own")
}

pub fn a_copy_links_to_the_new_plan_only_on_the_plan_it_came_from_test() {
  let model =
    Model(
      ..with_plans([mine("a", "A"), mine("b", "B")]),
      copy: plans_page.Copied("a", "new1"),
    )
  let on_source = html_of(plans_page.view_detail(model, "a", "u1"))
  assert string.contains(on_source, "Copied to your plans.")
  assert string.contains(on_source, "href=\"/plans/new1\"")
  // Closing the snackbar brings the Copy button back (ADR 0047).
  assert string.contains(on_source, "class=\"snackbar\"")
  assert string.contains(on_source, "aria-label=\"Close\"")
  let elsewhere = html_of(plans_page.view_detail(model, "b", "u1"))
  assert !string.contains(elsewhere, "Copied to your plans.")
  assert string.contains(elsewhere, "Copy to my plans")
}

pub fn the_copying_state_is_shown_test() {
  let model =
    Model(..with_plans([mine("a", "A")]), copy: plans_page.Copying("a"))
  assert string.contains(
    html_of(plans_page.view_detail(model, "a", "u1")),
    "Copying…",
  )
}
