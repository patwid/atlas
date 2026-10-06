//// The plan form: what the user typed, whether it is acceptable, and which fields to write.
//// Pure. The limits are those of the server (ADR 0009): a title of 1-200 characters and a description of up to 5000.

import atlas/outbox
import atlas/plan.{type Plan}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None}
import gleam/string

pub const max_title = 200

pub const max_description = 5000

pub type Form {
  Form(
    title: String,
    description: String,
    visibility: plan.Visibility,
    error: Option(String),
  )
}

/// A form that passed `validate`: trimmed and within the limits.
pub type Valid {
  Valid(title: String, description: String, visibility: plan.Visibility)
}

pub fn empty() -> Form {
  Form("", "", plan.Private, None)
}

pub fn from_plan(plan: Plan) -> Form {
  Form(plan.title, plan.description, plan.visibility, None)
}

pub fn visibility_from_string(text: String) -> plan.Visibility {
  case text {
    "public" -> plan.Public
    _ -> plan.Private
  }
}

pub fn validate(form: Form) -> Result(Valid, String) {
  let title = string.trim(form.title)
  let description = string.trim(form.description)
  case string.length(title), string.length(description) {
    0, _ -> Error("Give the plan a title.")
    n, _ if n > max_title -> Error("The title can have at most 200 characters.")
    _, n if n > max_description ->
      Error("The description can have at most 5000 characters.")
    _, _ -> Ok(Valid(title, description, form.visibility))
  }
}

/// The fields of a new plan. `owner_id` must be the signed-in user (the server checks it too).
pub fn create_fields(owner_id: String, valid: Valid) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("owner", owner_id),
    outbox.field_string("title", valid.title),
    outbox.field_string("description", valid.description),
    outbox.field_string(
      "visibility",
      plan.visibility_to_string(valid.visibility),
    ),
  ])
}

/// Only what differs from the plan as it is now, so an edit says exactly what the user changed.
/// Empty when nothing changed.
pub fn changed_fields(original: Plan, valid: Valid) -> outbox.Fields {
  [
    #(valid.title != original.title, outbox.field_string("title", valid.title)),
    #(
      valid.description != original.description,
      outbox.field_string("description", valid.description),
    ),
    #(
      valid.visibility != original.visibility,
      outbox.field_string(
        "visibility",
        plan.visibility_to_string(valid.visibility),
      ),
    ),
  ]
  |> list.filter(fn(item) { item.0 })
  |> list.map(fn(item) { item.1 })
  |> dict.from_list
}
