//// A plan's athlete: every plan has one assignment, made with the plan by its owner, for themselves or an athlete who
//// granted them access. It follows the plan's start date and never changes (ADR 0009, 0108, 0110). Pure.

import atlas/outbox
import atlas/plan.{type Assignment}
import gleam/dict
import gleam/list
import gleam/option.{type Option}

/// An assignment as stored, with the fields the domain type does not carry.
pub type Row {
  Row(assignment: Assignment, assigned_by: String, updated: String)
}

/// The fields of a plan's assignment. `owner_id` must be the signed-in user and the plan's owner (the server checks
/// it too); it follows the plan's start date, so it has none of its own.
pub fn create_fields(
  plan_id: String,
  owner_id: String,
  athlete_id: String,
) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("plan", plan_id),
    outbox.field_string("athlete", athlete_id),
    outbox.field_string("assigned_by", owner_id),
    outbox.field_string("start_date", ""),
  ])
}

/// The assignment of a plan, if the device has it.
pub fn of_plan(rows: List(Row), plan_id: String) -> Option(Row) {
  list.find(rows, fn(row) { row.assignment.plan_id == plan_id })
  |> option.from_result
}
