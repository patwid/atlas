import atlas/collection.{Plans}
import atlas/cursor.{Cursor, FullResync, Since}
import atlas/date.{Date}
import atlas/outbox
import gleam/dict
import gleam/option.{None, Some}

const today = Date(2026, 10, 6)

pub fn no_cursor_means_a_full_resync_test() {
  assert cursor.plan(None, today) == FullResync
}

pub fn a_recent_cursor_pulls_incrementally_test() {
  let c = Cursor("2026-10-05 08:00:00.000Z", Date(2026, 10, 5))
  assert cursor.plan(Some(c), today) == Since("2026-10-05 08:00:00.000Z")
  assert cursor.plan(Some(Cursor("T", today)), today) == Since("T")
}

pub fn a_stale_cursor_forces_a_full_resync_test() {
  // 80 days is the limit; one more day and tombstones may have been purged (ADR 0014).
  let at_limit = Cursor("T", date.add_days(today, -80))
  let past_limit = Cursor("T", date.add_days(today, -81))
  assert cursor.plan(Some(at_limit), today) == Since("T")
  assert cursor.plan(Some(past_limit), today) == FullResync
}

pub fn a_cursor_from_the_future_is_still_trusted_test() {
  // The device clock may have been set back. A negative age is not "too old".
  assert cursor.plan(Some(Cursor("T", date.add_days(today, 3))), today)
    == Since("T")
}

pub fn the_filter_uses_greater_or_equal_test() {
  assert cursor.filter(FullResync) == None
  assert cursor.filter(Since("2026-10-05 08:00:00.000Z"))
    == Some("updated >= \"2026-10-05 08:00:00.000Z\"")
  assert cursor.filter(Since("a\"b\\c")) == Some("updated >= \"a\\\"b\\\\c\"")
}

pub fn advance_takes_the_newest_updated_test() {
  let received = [
    "2026-10-05 09:00:00.000Z",
    "2026-10-05 11:30:00.123Z",
    "2026-10-05 10:00:00.000Z",
  ]
  assert cursor.advance(None, received, today)
    == Cursor("2026-10-05 11:30:00.123Z", today)
  let previous = Cursor("2026-10-01 00:00:00.000Z", Date(2026, 10, 1))
  assert cursor.advance(Some(previous), received, today)
    == Cursor("2026-10-05 11:30:00.123Z", today)
}

pub fn advance_never_moves_backwards_test() {
  let previous = Cursor("2026-10-05 12:00:00.000Z", Date(2026, 10, 5))
  assert cursor.advance(Some(previous), ["2026-10-01 00:00:00.000Z"], today)
    == Cursor("2026-10-05 12:00:00.000Z", today)
}

pub fn advance_without_records_only_moves_the_sync_day_test() {
  let previous = Cursor("2026-10-05 12:00:00.000Z", Date(2026, 10, 5))
  assert cursor.advance(Some(previous), [], today)
    == Cursor("2026-10-05 12:00:00.000Z", today)
  assert cursor.advance(None, [], today) == Cursor("", today)
}

pub fn records_with_unsent_edits_are_not_overwritten_test() {
  let ob =
    outbox.record_update(
      outbox.new(),
      Plans,
      "p1",
      dict.from_list([outbox.field_string("title", "mine")]),
      "T1",
    )
  assert !cursor.may_apply(ob, Plans, "p1")
  assert cursor.may_apply(ob, Plans, "p2")
  assert cursor.may_apply(outbox.new(), Plans, "p1")
}

pub fn a_cursor_survives_storage_test() {
  let c = Cursor("2026-10-05 08:00:00.123Z", Date(2026, 10, 5))
  assert cursor.from_json_string(cursor.to_json_string(c)) == Ok(c)
}

pub fn a_damaged_cursor_is_an_error_so_the_collection_resyncs_test() {
  assert cursor.from_json_string("") == Error(Nil)
  assert cursor.from_json_string("{}") == Error(Nil)
  assert cursor.from_json_string(
      "{\"updated\":\"T\",\"synced_on\":\"yesterday\"}",
    )
    == Error(Nil)
  assert cursor.from_json_string("{\"updated\":5,\"synced_on\":\"2026-10-05\"}")
    == Error(Nil)
}
