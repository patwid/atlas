//// What to do with an edit the server refused because the record changed elsewhere (ADR 0004, 0011).
//// For plans and workouts the user's version is kept as a new record, a "conflicted copy", and the
//// server's version takes the original's place. For everything else the server's version simply wins.
//// Pure: `syncing` does the reading and writing.

import atlas/collection.{type Collection}
import atlas/outbox
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

pub const copy_suffix = " (conflicted copy)"

/// Fields the server sets or owns. They are not copied into a new record.
const system_fields = [
  "id", "created", "updated", "collectionId", "collectionName", "expand",
  "deleted",
]

/// Only records that people write by hand are worth keeping a second version of. Matches and
/// coach grants are unique per activity or pair, activities from files are re-importable, and an
/// assignment only has a start date.
pub fn copyable(collection: Collection) -> Bool {
  case collection {
    collection.Plans | collection.Workouts -> True
    _ -> False
  }
}

/// The fields for the conflicted copy of a local record, given its stored fields as encoded JSON text
/// (see `store.record_fields`). `None` when there is nothing to keep: the collection is not copyable,
/// or the local version was a delete.
pub fn copy_fields(
  collection: Collection,
  stored: List(#(String, String)),
) -> Option(outbox.Fields) {
  let was_deleted =
    list.any(stored, fn(pair) { pair.0 == "deleted" && pair.1 == "true" })
  case copyable(collection), was_deleted {
    True, False ->
      stored
      |> list.filter(fn(pair) { !list.contains(system_fields, pair.0) })
      |> list.map(fn(pair) {
        case pair.0 {
          "title" -> outbox.field_string("title", with_suffix(pair.1))
          _ -> pair
        }
      })
      |> dict.from_list
      |> Some
    _, _ -> None
  }
}

/// The title of a stored record, for messages.
pub fn title_of(stored: List(#(String, String))) -> String {
  case list.find(stored, fn(pair) { pair.0 == "title" }) {
    Ok(#(_, text)) -> title_text(text)
    Error(Nil) -> ""
  }
}

fn with_suffix(encoded_title: String) -> String {
  title_text(encoded_title) <> copy_suffix
}

fn title_text(encoded: String) -> String {
  case json.parse(encoded, decode.string) {
    Ok(text) -> text
    Error(_) -> ""
  }
}
