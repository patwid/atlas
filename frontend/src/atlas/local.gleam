//// Opening the device database for a signed-in user and restoring the sync state saved in it.
//// Data on the device belongs to one user: if the stored owner is someone else, it is wiped first,
//// so a second person on a shared device never sees (or uploads) the first one's data (ADR 0017).

import atlas/collection.{type Collection}
import atlas/cursor.{type Cursor}
import atlas/outbox.{type Outbox}
import atlas/store
import gleam/list
import gleam/option.{type Option, None, Some}

pub const database_name = "atlas"

pub const outbox_key = "outbox"

const owner_key = "owner"

pub fn cursor_key(collection: Collection) -> String {
  "cursor:" <> collection.to_string(collection)
}

pub type Loaded {
  Loaded(outbox: Outbox, cursors: List(#(Collection, Cursor)))
}

/// The saved outbox. Nothing saved yet is an empty outbox; damaged text is an error, so that the app
/// stops instead of overwriting edits it could not read.
pub fn restore_outbox(text: String) -> Result(Outbox, Nil) {
  case text {
    "" -> Ok(outbox.new())
    _ -> outbox.from_json_string(text)
  }
}

/// A saved cursor, or `None` when there is none or it is damaged (the collection then does a full resync).
pub fn restore_cursor(text: String) -> Option(Cursor) {
  case cursor.from_json_string(text) {
    Ok(c) -> Some(c)
    Error(Nil) -> None
  }
}

/// Opens the database for this user, clears it if it belongs to someone else, and loads the sync state.
pub fn load(user_id: String, callback: fn(Result(Loaded, Nil)) -> Nil) -> Nil {
  store.open(database_name, fn(opened) {
    case opened {
      False -> callback(Error(Nil))
      True ->
        store.get_meta(owner_key, fn(owner) {
          case owner {
            Error(Nil) -> callback(Error(Nil))
            Ok(owner) if owner == user_id -> load_state(callback)
            Ok(_) ->
              // Empty or someone else's: start clean and claim the database.
              store.clear(fn(cleared) {
                case cleared {
                  False -> callback(Error(Nil))
                  True ->
                    store.put_meta(owner_key, user_id, fn(saved) {
                      case saved {
                        True -> load_state(callback)
                        False -> callback(Error(Nil))
                      }
                    })
                }
              })
          }
        })
    }
  })
}

fn load_state(callback: fn(Result(Loaded, Nil)) -> Nil) -> Nil {
  store.get_meta(outbox_key, fn(text) {
    case text {
      Error(Nil) -> callback(Error(Nil))
      Ok(text) ->
        case restore_outbox(text) {
          Error(Nil) -> callback(Error(Nil))
          Ok(box) ->
            load_cursors(collection.all, [], fn(cursors) {
              callback(Ok(Loaded(box, cursors)))
            })
        }
    }
  })
}

fn load_cursors(
  remaining: List(Collection),
  found: List(#(Collection, Cursor)),
  done: fn(List(#(Collection, Cursor))) -> Nil,
) -> Nil {
  case remaining {
    [] -> done(list.reverse(found))
    [next, ..rest] ->
      store.get_meta(cursor_key(next), fn(text) {
        case text {
          Ok(text) ->
            case restore_cursor(text) {
              Some(c) -> load_cursors(rest, [#(next, c), ..found], done)
              None -> load_cursors(rest, found, done)
            }
          Error(Nil) -> load_cursors(rest, found, done)
        }
      })
  }
}
