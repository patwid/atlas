import atlas/outbox
import atlas/plan.{Plan}
import atlas/plan_form.{Form, Valid}
import gleam/dict
import gleam/option.{None}
import gleam/string

fn form(title: String, description: String) -> plan_form.Form {
  Form(title, description, plan.Private, None)
}

pub fn a_title_is_required_test() {
  assert plan_form.validate(form("", "x")) == Error("Give the plan a title.")
  assert plan_form.validate(form("   \n ", ""))
    == Error("Give the plan a title.")
}

pub fn input_is_trimmed_test() {
  assert plan_form.validate(form("  10k plan  ", "  Build up\n"))
    == Ok(Valid("10k plan", "Build up", plan.Private))
}

pub fn the_description_may_be_empty_test() {
  assert plan_form.validate(form("Plan", ""))
    == Ok(Valid("Plan", "", plan.Private))
}

pub fn the_server_limits_are_enforced_before_sending_test() {
  assert plan_form.validate(form(string.repeat("a", 200), ""))
    == Ok(Valid(string.repeat("a", 200), "", plan.Private))
  assert plan_form.validate(form(string.repeat("a", 201), ""))
    == Error("The title can have at most 200 characters.")
  assert plan_form.validate(form("T", string.repeat("b", 5000)))
    == Ok(Valid("T", string.repeat("b", 5000), plan.Private))
  assert plan_form.validate(form("T", string.repeat("b", 5001)))
    == Error("The description can have at most 5000 characters.")
}

pub fn visibility_comes_from_the_select_value_test() {
  assert plan_form.visibility_from_string("public") == plan.Public
  assert plan_form.visibility_from_string("private") == plan.Private
  assert plan_form.visibility_from_string("anything else") == plan.Private
}

pub fn a_new_plan_carries_its_owner_and_every_field_test() {
  let valid = Valid("10k", "Build up", plan.Public)
  assert plan_form.create_fields("u1", valid)
    == dict.from_list([
      outbox.field_string("owner", "u1"),
      outbox.field_string("title", "10k"),
      outbox.field_string("description", "Build up"),
      outbox.field_string("visibility", "public"),
    ])
}

fn existing() -> plan.Plan {
  Plan("p1", "u1", "10k", "Build up", plan.Private, "T1")
}

pub fn an_edit_sends_only_what_changed_test() {
  assert plan_form.changed_fields(
      existing(),
      Valid("Half marathon", "Build up", plan.Private),
    )
    == dict.from_list([outbox.field_string("title", "Half marathon")])
  assert plan_form.changed_fields(
      existing(),
      Valid("10k", "Build up", plan.Public),
    )
    == dict.from_list([outbox.field_string("visibility", "public")])
  assert plan_form.changed_fields(
      existing(),
      Valid("New", "Other", plan.Public),
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
      Valid("10k", "Build up", plan.Private),
    )
    == dict.new()
}

pub fn editing_starts_from_the_plan_test() {
  assert plan_form.from_plan(existing())
    == Form("10k", "Build up", plan.Private, None)
  assert plan_form.empty() == Form("", "", plan.Private, None)
}
