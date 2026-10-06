//// Plan shares: who a plan is shared with (ADR 0009, 0029). A share is read access for a named user.
//// The names come with the share so that screens can show them offline.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Share {
  Share(
    id: String,
    plan_id: String,
    user_id: String,
    /// The person the plan is shared with.
    user_name: String,
    /// The owner who shared it.
    shared_by_name: String,
    /// Removed shares stay as rows: a pair of plan and user has one row, which sharing again reuses.
    deleted: Bool,
    /// The `updated` value of the local copy: the base for edits (ADR 0011).
    updated: String,
  )
}

/// The people a plan is currently shared with, by name.
pub fn current_for(shares: List(Share), plan_id: String) -> List(Share) {
  shares
  |> list.filter(fn(s) { s.plan_id == plan_id && !s.deleted })
  |> list.sort(fn(a, b) {
    string.compare(string.lowercase(a.user_name), string.lowercase(b.user_name))
  })
}

/// Whether the plan is shared with `user_id` right now.
pub fn is_shared_with(
  shares: List(Share),
  plan_id: String,
  user_id: String,
) -> Bool {
  list.any(shares, fn(s) {
    s.plan_id == plan_id && s.user_id == user_id && !s.deleted
  })
}

/// The row for a plan and a user, removed or not, so that sharing again can reuse it.
pub fn row_for(
  shares: List(Share),
  plan_id: String,
  user_id: String,
) -> Option(Share) {
  case
    list.find(shares, fn(s) { s.plan_id == plan_id && s.user_id == user_id })
  {
    Ok(found) -> Some(found)
    Error(Nil) -> None
  }
}

/// Who shared the plan with `me`, when it is.
pub fn shared_by(
  shares: List(Share),
  plan_id: String,
  me: String,
) -> Option(String) {
  case
    list.find(shares, fn(s) {
      s.plan_id == plan_id && s.user_id == me && !s.deleted
    })
  {
    Ok(s) ->
      case string.trim(s.shared_by_name) {
        "" -> Some("someone")
        name -> Some(name)
      }
    Error(Nil) -> None
  }
}
