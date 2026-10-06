import atlas/collection.{Plans}
import atlas/cursor.{Cursor}
import atlas/date.{Date}
import atlas/local
import atlas/outbox
import gleam/dict
import gleam/option.{None, Some}

pub fn nothing_saved_is_an_empty_outbox_test() {
  assert local.restore_outbox("") == Ok(outbox.new())
}

pub fn a_saved_outbox_is_restored_test() {
  let box =
    outbox.record_create(
      outbox.new(),
      Plans,
      "p1",
      dict.from_list([outbox.field_string("title", "A")]),
    )
  assert local.restore_outbox(outbox.to_json_string(box)) == Ok(box)
}

pub fn a_damaged_outbox_is_an_error_not_an_empty_one_test() {
  // An empty outbox here would be overwritten on the next save and lose the user's unsent edits.
  assert local.restore_outbox("{not json") == Error(Nil)
  assert local.restore_outbox("{}") == Error(Nil)
}

pub fn cursors_restore_or_fall_back_to_a_full_resync_test() {
  let c = Cursor("2026-10-05 08:00:00.000Z", Date(2026, 10, 5))
  assert local.restore_cursor(cursor.to_json_string(c)) == Some(c)
  assert local.restore_cursor("") == None
  assert local.restore_cursor("damaged") == None
}

pub fn storage_keys_are_stable_test() {
  assert local.outbox_key == "outbox"
  assert local.cursor_key(Plans) == "cursor:plans"
  assert local.database_name == "atlas"
}
