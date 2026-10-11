import atlas/date.{Date}
import atlas/outbox
import atlas/plan.{Phases}
import atlas/plan_form.{Form, Settings, Valid, ValidSettings}
import gleam/dict
import gleam/option.{None, Some}
import gleam/string

fn form(title: String, description: String) -> plan_form.Form {
  Form(
    title,
    description,
    "u1",
    "2026-11-02",
    True,
    plan_form.default_settings(),
    None,
  )
}

pub fn a_title_is_required_test() {
  assert plan_form.validate(form("", "x")) == Error("Give the plan a title.")
  assert plan_form.validate(form("   \n ", ""))
    == Error("Give the plan a title.")
}

pub fn input_is_trimmed_test() {
  assert plan_form.validate(form("  10k plan  ", "  Build up\n"))
    == Ok(Valid("10k plan", "Build up", Some(Date(2026, 11, 2)), defaults()))
}

pub fn the_description_may_be_empty_test() {
  assert plan_form.validate(form("Plan", ""))
    == Ok(Valid("Plan", "", Some(Date(2026, 11, 2)), defaults()))
}

pub fn the_server_limits_are_enforced_before_sending_test() {
  assert plan_form.validate(form(string.repeat("a", 200), ""))
    == Ok(Valid(
      string.repeat("a", 200),
      "",
      Some(Date(2026, 11, 2)),
      defaults(),
    ))
  assert plan_form.validate(form(string.repeat("a", 201), ""))
    == Error("The title can have at most 200 characters.")
  assert plan_form.validate(form("T", string.repeat("b", 5000)))
    == Ok(Valid(
      "T",
      string.repeat("b", 5000),
      Some(Date(2026, 11, 2)),
      defaults(),
    ))
  assert plan_form.validate(form("T", string.repeat("b", 5001)))
    == Error("The description can have at most 5000 characters.")
}

pub fn a_new_plan_carries_its_owner_and_every_field_test() {
  let valid = Valid("10k", "Build up", Some(Date(2026, 11, 2)), defaults())
  assert plan_form.create_fields("u1", valid)
    == dict.from_list([
      outbox.field_string("owner", "u1"),
      outbox.field_string("title", "10k"),
      outbox.field_string("description", "Build up"),
      outbox.field_string("start_date", "2026-11-02"),
      outbox.field_int("base_weeks", 4),
      outbox.field_int("pre_competition_weeks", 4),
      outbox.field_int("competition_weeks", 4),
      outbox.field_float("weekly_distance_m", 0.0),
    ])
}

fn existing() -> plan.Plan {
  plan.Plan(
    ..plan.new("p1", "u1", "10k", "Build up", "T1"),
    phases: Phases(4, 4, 4),
    start_date: Some(Date(2026, 11, 2)),
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
  let old = plan.new("p", "u", "Old", "", "T")
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
  assert plan_form.intensity_fields(p, 3, Some(0.8))
    == dict.from_list([#("week_intensity", "[null,null,0.8]")])
  let with_two =
    plan.Plan(..p, week_intensity: dict.from_list([#(5, 0.3), #(3, 0.8)]))
  assert plan_form.intensity_fields(with_two, 2, Some(0.55))
    == dict.from_list([#("week_intensity", "[null,0.55,0.8,null,0.3]")])
  assert plan_form.intensity_fields(with_two, 3, None)
    == dict.from_list([#("week_intensity", "[null,null,null,null,0.3]")])
  assert plan_form.intensity_fields(with_two, 3, Some(0.8)) == dict.new()
  assert plan_form.intensity_fields(with_two, 4, None) == dict.new()
}

pub fn an_intensity_stays_within_0_and_1_in_whole_percent_test() {
  let p = existing()
  assert plan_form.intensity_fields(p, 1, Some(1.7))
    == dict.from_list([#("week_intensity", "[1]")])
  assert plan_form.intensity_fields(p, 1, Some(0.123))
    == dict.from_list([#("week_intensity", "[0.12]")])
  assert plan_form.intensity_fields(p, 1, Some(-0.2))
    == dict.from_list([#("week_intensity", "[0]")])
}

pub fn an_edit_sends_only_what_changed_test() {
  assert plan_form.changed_fields(
      existing(),
      Valid("Half marathon", "Build up", Some(Date(2026, 11, 2)), defaults()),
    )
    == dict.from_list([outbox.field_string("title", "Half marathon")])
  assert plan_form.changed_fields(
      existing(),
      Valid("New", "Other", Some(Date(2026, 11, 2)), defaults()),
    )
    == dict.from_list([
      outbox.field_string("title", "New"),
      outbox.field_string("description", "Other"),
    ])
}

pub fn an_unchanged_edit_sends_nothing_test() {
  assert plan_form.changed_fields(
      existing(),
      Valid("10k", "Build up", Some(Date(2026, 11, 2)), defaults()),
    )
    == dict.new()
}

pub fn editing_starts_from_the_plan_test() {
  assert plan_form.from_plan(existing())
    == Form(
      "10k",
      "Build up",
      "",
      "2026-11-02",
      True,
      Settings("4", "4", "4", ""),
      None,
    )
  // A new plan starts on the coming Monday: Sunday 11 Oct gives Monday 12 Oct.
  assert plan_form.empty(Date(2026, 10, 11), "u1")
    == Form("", "", "u1", "2026-10-12", True, Settings("4", "4", "4", ""), None)
}

pub fn a_problem_names_its_field_test() {
  assert plan_form.error_field(form("", "x")) == "title"
  assert plan_form.error_field(
      Form(..form("Plan", ""), settings: Settings("0", "0", "0", "")),
    )
    == "phases"
  assert plan_form.settings_error_field(Settings("4", "4", "4", "far"))
    == "goal"
  assert plan_form.error_field(form("Plan", "")) == ""
}

pub fn a_new_plan_needs_a_start_date_an_old_one_may_go_without_test() {
  assert plan_form.validate_fields(Form(..form("Plan", ""), start_date: ""))
    == Error(#("start", "Pick the plan's first day."))
  assert plan_form.validate_fields(
      Form(..form("Plan", ""), start_date: "1999-12-27"),
    )
    == Error(#(
      "start",
      "The start date must be between the years 2000 and 2100.",
    ))
  let undated =
    plan.Plan(..plan.new("p2", "u1", "Old", "", "T1"), phases: Phases(4, 4, 4))
  let assert Ok(valid) = plan_form.validate(plan_form.from_plan(undated))
  assert valid.start_date == None
  assert plan_form.changed_fields(undated, valid) == dict.new()
}

pub fn moving_the_start_is_one_field_test() {
  let assert Ok(valid) =
    plan_form.validate(
      Form(..plan_form.from_plan(existing()), start_date: "2026-11-09"),
    )
  assert plan_form.changed_fields(existing(), valid)
    == dict.from_list([outbox.field_string("start_date", "2026-11-09")])
}
