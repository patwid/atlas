import atlas/assignment_form.{Row}
import atlas/outbox
import atlas/plan.{Assignment}
import gleam/dict
import gleam/option.{None, Some}

pub fn a_plans_assignment_follows_the_plan_and_is_made_by_its_owner_test() {
  assert assignment_form.create_fields("p1", "coach", "ana")
    == dict.from_list([
      outbox.field_string("plan", "p1"),
      outbox.field_string("athlete", "ana"),
      outbox.field_string("assigned_by", "coach"),
      outbox.field_string("start_date", ""),
    ])
}

pub fn the_assignment_of_a_plan_is_found_by_the_plan_test() {
  let row = fn(id, plan_id) {
    Row(Assignment(id, plan_id, "me", None), "me", "T")
  }
  let rows = [row("a", "p1"), row("b", "p2")]
  assert assignment_form.of_plan(rows, "p2") == Some(row("b", "p2"))
  assert assignment_form.of_plan(rows, "p3") == None
}
