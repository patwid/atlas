import atlas/outbox
import atlas/plan.{Phases}
import atlas/plan_form.{Form, Settings, Valid, ValidSettings}
import gleam/dict
import gleam/option.{None, Some}
import gleam/string

fn form(title: String, description: String) -> plan_form.Form {
  Form(title, description, plan.Private, plan_form.default_settings(), None)
}

pub fn a_title_is_required_test() {
  assert plan_form.validate(form("", "x")) == Error("Give the plan a title.")
  assert plan_form.validate(form("   \n ", ""))
    == Error("Give the plan a title.")
}

pub fn input_is_trimmed_test() {
  assert plan_form.validate(form("  10k plan  ", "  Build up\n"))
    == Ok(Valid("10k plan", "Build up", plan.Private, defaults()))
}

pub fn the_description_may_be_empty_test() {
  assert plan_form.validate(form("Plan", ""))
    == Ok(Valid("Plan", "", plan.Private, defaults()))
}

pub fn the_server_limits_are_enforced_before_sending_test() {
  assert plan_form.validate(form(string.repeat("a", 200), ""))
    == Ok(Valid(string.repeat("a", 200), "", plan.Private, defaults()))
  assert plan_form.validate(form(string.repeat("a", 201), ""))
    == Error("The title can have at most 200 characters.")
  assert plan_form.validate(form("T", string.repeat("b", 5000)))
    == Ok(Valid("T", string.repeat("b", 5000), plan.Private, defaults()))
  assert plan_form.validate(form("T", string.repeat("b", 5001)))
    == Error("The description can have at most 5000 characters.")
}

pub fn visibility_comes_from_the_select_value_test() {
  assert plan_form.visibility_from_string("public") == plan.Public
  assert plan_form.visibility_from_string("private") == plan.Private
  assert plan_form.visibility_from_string("anything else") == plan.Private
}

pub fn a_new_plan_carries_its_owner_and_every_field_test() {
  let valid = Valid("10k", "Build up", plan.Public, defaults())
  assert plan_form.create_fields("u1", valid)
    == dict.from_list([
      outbox.field_string("owner", "u1"),
      outbox.field_string("title", "10k"),
      outbox.field_string("description", "Build up"),
      outbox.field_string("visibility", "public"),
      outbox.field_int("base_weeks", 4),
      outbox.field_int("pre_competition_weeks", 4),
      outbox.field_int("competition_weeks", 4),
      outbox.field_float("weekly_distance_m", 0.0),
    ])
}

fn existing() -> plan.Plan {
  plan.Plan(
    ..plan.new("p1", "u1", "10k", "Build up", plan.Private, "T1"),
    phases: Phases(4, 4, 4),
  )
}

fn defaults() -> plan_form.ValidSettings {
  ValidSettings(Phases(4, 4, 4), 0.0)
}

fn settings(base: String, pre: String, competition: String, goal: String) {
  plan_form.validate_settings(Settings(base, pre, competition, goal))
}

pub fn phases_and_goal_are_validated_test() {
  assert settings("4", "4", "4", "") == Ok(defaults())
  assert settings(" 6 ", "0", "2", "42,5")
    == Ok(ValidSettings(Phases(6, 0, 2), 42_500.0))
  assert settings("0", "0", "0", "")
    == Error("The plan needs at least one week.")
  assert settings("53", "0", "0", "")
    == Error("The base phase must be a number of weeks from 0 to 52.")
  assert settings("4", "x", "4", "")
    == Error(
      "The pre-competition phase must be a number of weeks from 0 to 52.",
    )
  assert settings("30", "30", "1", "")
    == Error("The phases can last at most 60 weeks together.")
  assert settings("4", "4", "4", "fast")
    == Error("Enter the weekly distance goal in kilometres, for example 40.")
  assert settings("4", "4", "4", "1001")
    == Error("The weekly distance goal can be at most 1000 km.")
}

pub fn a_plan_without_phases_is_offered_the_default_ones_test() {
  let old = plan.new("p", "u", "Old", "", plan.Private, "T")
  assert plan_form.settings_from(old) == Settings("4", "4", "4", "")
  let with_goal =
    plan.Plan(..old, phases: Phases(8, 2, 1), weekly_distance_m: Some(40_000.0))
  assert plan_form.settings_from(with_goal) == Settings("8", "2", "1", "40")
}

pub fn changed_settings_send_only_what_changed_test() {
  assert plan_form.changed_settings_fields(existing(), defaults()) == dict.new()
  assert plan_form.changed_settings_fields(
      existing(),
      ValidSettings(Phases(4, 6, 4), 40_000.0),
    )
    == dict.from_list([
      outbox.field_int("pre_competition_weeks", 6),
      outbox.field_float("weekly_distance_m", 40_000.0),
    ])
}

pub fn setting_a_week_intensity_writes_all_of_them_test() {
  let p = existing()
  assert plan_form.intensity_fields(p, 3, Some(plan.High))
    == dict.from_list([#("week_intensity", "{\"3\":\"high\"}")])
  let with_two =
    plan.Plan(
      ..p,
      week_intensity: dict.from_list([#(10, plan.Low), #(3, plan.High)]),
    )
  assert plan_form.intensity_fields(with_two, 2, Some(plan.Medium))
    == dict.from_list([
      #("week_intensity", "{\"2\":\"medium\",\"3\":\"high\",\"10\":\"low\"}"),
    ])
  assert plan_form.intensity_fields(with_two, 3, None)
    == dict.from_list([#("week_intensity", "{\"10\":\"low\"}")])
  assert plan_form.intensity_fields(with_two, 3, Some(plan.High)) == dict.new()
  assert plan_form.intensity_fields(with_two, 4, None) == dict.new()
}

pub fn an_edit_sends_only_what_changed_test() {
  assert plan_form.changed_fields(
      existing(),
      Valid("Half marathon", "Build up", plan.Private, defaults()),
    )
    == dict.from_list([outbox.field_string("title", "Half marathon")])
  assert plan_form.changed_fields(
      existing(),
      Valid("10k", "Build up", plan.Public, defaults()),
    )
    == dict.from_list([outbox.field_string("visibility", "public")])
  assert plan_form.changed_fields(
      existing(),
      Valid("New", "Other", plan.Public, defaults()),
    )
    == dict.from_list([
      outbox.field_string("title", "New"),
      outbox.field_string("description", "Other"),
      outbox.field_string("visibility", "public"),
    ])
}

pub fn an_unchanged_edit_sends_nothing_test() {
  assert plan_form.changed_fields(
      existing(),
      Valid("10k", "Build up", plan.Private, defaults()),
    )
    == dict.new()
}

pub fn editing_starts_from_the_plan_test() {
  assert plan_form.from_plan(existing())
    == Form("10k", "Build up", plan.Private, Settings("4", "4", "4", ""), None)
  assert plan_form.empty()
    == Form("", "", plan.Private, Settings("4", "4", "4", ""), None)
}
