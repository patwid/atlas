//// Starting a plan on a date, for oneself or for an athlete. Pure: validating the date and choosing the
//// fields to write (ADR 0009, 0023).

import atlas/date.{type Date}
import atlas/outbox
import atlas/plan.{type Assignment}
import gleam/dict
import gleam/option.{type Option, None}

/// Dates outside this range are certainly typing mistakes.
const earliest_year = 2000

const latest_year = 2100

pub type Form {
  Form(
    /// The athlete the plan is for: the signed-in user, or an athlete who granted access.
    athlete_id: String,
    /// As typed or picked: `YYYY-MM-DD`.
    start_date: String,
    error: Option(String),
  )
}

pub type Valid {
  Valid(athlete_id: String, start: Date)
}

/// An assignment as stored, with the fields the domain type does not carry.
pub type Row {
  Row(assignment: Assignment, assigned_by: String, updated: String)
}

pub fn empty_for(athlete_id: String, today: Date) -> Form {
  Form(athlete_id, date.to_string(today), None)
}

pub fn from_row(row: Row) -> Form {
  Form(
    row.assignment.athlete_id,
    date.to_string(row.assignment.start_date),
    None,
  )
}

pub fn validate(form: Form) -> Result(Valid, String) {
  case form.athlete_id, date.parse(form.start_date) {
    "", _ -> Error("Choose who the plan is for.")
    _, Error(Nil) -> Error("Pick a start date.")
    _, Ok(start) ->
      case start.year < earliest_year || start.year > latest_year {
        True -> Error("The start date must be between the years 2000 and 2100.")
        False -> Ok(Valid(form.athlete_id, start))
      }
  }
}

/// The fields of a new assignment. `assigned_by` must be the signed-in user (the server checks it too).
pub fn create_fields(
  plan_id: String,
  assigned_by: String,
  valid: Valid,
) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("plan", plan_id),
    outbox.field_string("athlete", valid.athlete_id),
    outbox.field_string("assigned_by", assigned_by),
    outbox.field_string("start_date", date.to_string(valid.start)),
  ])
}

/// Only the start date can change afterwards (the plan and the athlete are fixed, 0009).
/// Empty when it is the same.
pub fn changed_fields(row: Row, valid: Valid) -> outbox.Fields {
  case valid.start == row.assignment.start_date {
    True -> dict.new()
    False ->
      dict.from_list([
        outbox.field_string("start_date", date.to_string(valid.start)),
      ])
  }
}
