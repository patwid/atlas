//// Starting a plan, for oneself or for an athlete: on the plan's own start date, which the assignment then follows,
//// or on a date of its own. Pure: validating the date and choosing the fields to write (ADR 0009, 0023, 0108).

import atlas/date.{type Date}
import atlas/outbox
import atlas/plan.{type Assignment}
import gleam/dict
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

/// Dates outside this range are certainly typing mistakes.
const earliest_year = 2000

const latest_year = 2100

pub type Form {
  Form(
    /// The athlete the plan is for: the signed-in user, or an athlete who granted access.
    athlete_id: String,
    /// As typed or picked: `YYYY-MM-DD`. Not used while `follows_plan`.
    start_date: String,
    /// The assignment follows the plan's start date rather than having its own (ADR 0108).
    follows_plan: Bool,
    error: Option(String),
  )
}

pub type Valid {
  /// `start` None: follows the plan's start date.
  Valid(athlete_id: String, start: Option(Date))
}

/// An assignment as stored, with the fields the domain type does not carry.
pub type Row {
  Row(assignment: Assignment, assigned_by: String, updated: String)
}

/// Starting a plan. One's own plan with a start date is followed: moving the plan moves the assignment. Someone
/// else's plan gets a date of its own, the plan's if it has not passed, else the coming Monday (ADR 0108).
pub fn empty_for(
  athlete_id: String,
  plan_start: Option(Date),
  own_plan: Bool,
  today: Date,
) -> Form {
  let follows = own_plan && plan_start != None
  let start = case plan_start {
    Some(day) ->
      case date.compare(day, today) {
        order.Lt -> plan.coming_monday(today)
        _ -> day
      }
    None -> plan.coming_monday(today)
  }
  Form(athlete_id, date.to_string(start), follows, None)
}

/// Changing the date of an assignment gives it a date of its own; it starts as the one it has now.
pub fn from_row(row: Row, plan_start: Option(Date)) -> Form {
  Form(
    row.assignment.athlete_id,
    case option.or(row.assignment.start_date, plan_start) {
      Some(day) -> date.to_string(day)
      None -> ""
    },
    False,
    None,
  )
}

/// Checks the form; a problem names the field it is about: `athlete` or `start`.
pub fn validate_fields(form: Form) -> Result(Valid, #(String, String)) {
  case form.athlete_id, date.parse(form.start_date) {
    "", _ -> Error(#("athlete", "Choose who the plan is for."))
    athlete_id, _ if form.follows_plan -> Ok(Valid(athlete_id, None))
    _, Error(Nil) -> Error(#("start", "Pick a start date."))
    _, Ok(start) ->
      case start.year < earliest_year || start.year > latest_year {
        True ->
          Error(#(
            "start",
            "The start date must be between the years 2000 and 2100.",
          ))
        False -> Ok(Valid(form.athlete_id, Some(start)))
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
    outbox.field_string("start_date", start_text(valid.start)),
  ])
}

/// Empty for following the plan.
fn start_text(start: Option(Date)) -> String {
  case start {
    Some(day) -> date.to_string(day)
    None -> ""
  }
}

/// Only the start date can change afterwards (the plan and the athlete are fixed, 0009).
/// Empty when it is the same.
pub fn changed_fields(row: Row, valid: Valid) -> outbox.Fields {
  case valid.start == row.assignment.start_date {
    True -> dict.new()
    False ->
      dict.from_list([
        outbox.field_string("start_date", start_text(valid.start)),
      ])
  }
}

/// The form's problem without the field it is about (ADR 0059).
pub fn validate(form: Form) -> Result(Valid, String) {
  validate_fields(form) |> result.map_error(fn(problem) { problem.1 })
}

/// The field the form's problem is about, `""` when there is none: its error is shown under that field (ADR 0059).
pub fn error_field(form: Form) -> String {
  case validate_fields(form) {
    Error(#(field, _)) -> field
    Ok(_) -> ""
  }
}
