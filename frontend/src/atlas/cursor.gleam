//// Pull side of sync (ADR 0004): each collection is pulled for records changed since a cursor.
//// The cursor is the largest `updated` seen. A device that has not synced for longer than the server
//// keeps tombstones (ADR 0014) must start over, because it could have missed deletions.

import atlas/collection.{type Collection}
import atlas/date.{type Date}
import atlas/outbox.{type Outbox}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

/// The server purges tombstones after 90 days (ADR 0014). A cursor older than this margin is not trusted.
pub const max_cursor_age_days = 80

pub type Cursor {
  Cursor(
    /// The largest `updated` value seen, as the server formats it.
    updated: String,
    /// The local calendar day of the last completed pull.
    synced_on: Date,
  )
}

pub type PullPlan {
  /// Fetch everything and replace the local copy, tombstones included. Nothing is known yet,
  /// or too much time has passed.
  FullResync
  /// Fetch records changed since the cursor.
  Since(updated: String)
}

pub fn plan(cursor: Option(Cursor), today: Date) -> PullPlan {
  case cursor {
    None -> FullResync
    Some(c) ->
      case date.diff_days(from: c.synced_on, to: today) > max_cursor_age_days {
        True -> FullResync
        False -> Since(c.updated)
      }
  }
}

/// The PocketBase `filter` for an incremental pull. It is `>=`, not `>`: two records saved in the
/// same millisecond, or one that commits a moment late, would otherwise be skipped. Applying a
/// record twice is harmless, because applying is an upsert.
pub fn filter(plan: PullPlan) -> Option(String) {
  case plan {
    FullResync -> None
    Since(updated) -> Some("updated >= \"" <> escape(updated) <> "\"")
  }
}

/// Moves the cursor after a complete pull. The `updated` values of the records received are
/// compared as text, which orders correctly for PocketBase's fixed-width format.
/// Without records the cursor keeps its value and only the sync day moves.
pub fn advance(
  previous: Option(Cursor),
  received: List(String),
  today: Date,
) -> Cursor {
  let newest = case list.sort(received, fn(a, b) { string.compare(b, a) }) {
    [latest, ..] -> Some(latest)
    [] -> None
  }
  case previous, newest {
    Some(c), Some(latest) ->
      case string.compare(latest, c.updated) {
        order.Lt -> Cursor(c.updated, today)
        _ -> Cursor(latest, today)
      }
    Some(c), None -> Cursor(c.updated, today)
    None, Some(latest) -> Cursor(latest, today)
    None, None -> Cursor("", today)
  }
}

/// Whether a pulled record may overwrite the local copy. A record with unsent local edits is left
/// alone: the server version is kept for the conflict check when the edit is sent (ADR 0011).
pub fn may_apply(outbox: Outbox, collection: Collection, id: String) -> Bool {
  !outbox.has_pending(outbox, collection, id)
}

fn escape(text: String) -> String {
  text |> string.replace("\\", "\\\\") |> string.replace("\"", "\\\"")
}

/// For storing a cursor on the device.
pub fn to_json_string(cursor: Cursor) -> String {
  json.object([
    #("updated", json.string(cursor.updated)),
    #("synced_on", json.string(date.to_string(cursor.synced_on))),
  ])
  |> json.to_string
}

/// `Error` for anything damaged, which makes the collection start over with a full resync.
pub fn from_json_string(text: String) -> Result(Cursor, Nil) {
  let decoder = {
    use updated <- decode.field("updated", decode.string)
    use synced_on <- decode.field("synced_on", decode.string)
    decode.success(#(updated, synced_on))
  }
  case json.parse(text, decoder) {
    Ok(#(updated, synced_on)) ->
      case date.parse(synced_on) {
        Ok(day) -> Ok(Cursor(updated, day))
        Error(Nil) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}
