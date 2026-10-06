import atlas/collection.{Plans, Workouts}
import atlas/outbox.{
  AlreadyExists, Conflict, Conflicted, Continue, Create, Failed, NeedsSignIn,
  NetworkError, Rejected, RetryAfter, Saved, Unauthorized, Update,
}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

fn fields(pairs: List(#(String, String))) -> outbox.Fields {
  dict.from_list(pairs)
}

fn title(value: String) -> outbox.Fields {
  fields([outbox.field_string("title", value)])
}

fn seqs(ob: outbox.Outbox) -> List(Int) {
  list.map(ob.entries, fn(e) { e.seq })
}

fn head(ob: outbox.Outbox) -> outbox.Entry {
  let assert Some(entry) = outbox.next(ob)
  entry
}

pub fn a_new_outbox_is_empty_test() {
  assert outbox.is_empty(outbox.new())
  assert outbox.pending_count(outbox.new()) == 0
  assert outbox.next(outbox.new()) == None
}

pub fn edits_to_an_unsent_create_merge_into_it_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(
      Plans,
      "p1",
      fields([
        outbox.field_string("title", "A"),
        outbox.field_string("visibility", "private"),
      ]),
    )
    |> outbox.record_update(Plans, "p1", title("B"), "ignored")
    |> outbox.record_update(
      Plans,
      "p1",
      fields([outbox.field_string("description", "x")]),
      "ignored",
    )
  assert outbox.pending_count(ob) == 1
  let entry = head(ob)
  assert entry.kind == Create
  assert entry.base_updated == None
  assert entry.fields
    == fields([
      outbox.field_string("title", "B"),
      outbox.field_string("visibility", "private"),
      outbox.field_string("description", "x"),
    ])
}

pub fn deleting_an_unsent_create_cancels_it_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.record_create(Plans, "p2", title("B"))
    |> outbox.record_delete(Plans, "p1", "ignored")
  assert outbox.pending_count(ob) == 1
  assert head(ob).id == "p2"
}

pub fn an_edit_of_a_synced_record_carries_its_base_test() {
  let ob =
    outbox.record_update(
      outbox.new(),
      Plans,
      "p1",
      title("A"),
      "2026-10-01 07:00:00.000Z",
    )
  let entry = head(ob)
  assert entry.kind == Update
  assert entry.base_updated == Some("2026-10-01 07:00:00.000Z")
  assert !outbox.needs_base(entry)
}

pub fn further_edits_keep_the_first_base_and_merge_test() {
  let ob =
    outbox.new()
    |> outbox.record_update(Plans, "p1", title("A"), "T1")
    |> outbox.record_update(Plans, "p1", title("B"), "T1")
  assert outbox.pending_count(ob) == 1
  assert head(ob).fields == title("B")
  assert head(ob).base_updated == Some("T1")
}

pub fn deleting_a_synced_record_is_a_soft_delete_update_test() {
  let ob = outbox.record_delete(outbox.new(), Plans, "p1", "T1")
  let entry = head(ob)
  assert entry.kind == Update
  assert entry.fields == fields([outbox.field_bool("deleted", True)])
  assert entry.base_updated == Some("T1")
}

pub fn deleting_after_an_unsent_edit_merges_test() {
  let ob =
    outbox.new()
    |> outbox.record_update(Plans, "p1", title("A"), "T1")
    |> outbox.record_delete(Plans, "p1", "T1")
  assert outbox.pending_count(ob) == 1
  assert head(ob).fields
    == fields([
      outbox.field_string("title", "A"),
      outbox.field_bool("deleted", True),
    ])
}

pub fn entries_are_sent_strictly_one_at_a_time_in_order_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.record_create(Workouts, "w1", title("W"))
  assert head(ob).id == "p1"
  let sending = outbox.mark_sending(ob, head(ob).seq)
  assert outbox.next(sending) == None
  let #(after, outcome) = outbox.handle_response(sending, 1, Saved("T1"))
  assert outcome == Continue
  assert head(after).id == "w1"
}

pub fn a_saved_entry_leaves_the_outbox_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(after, outcome) =
    outbox.handle_response(outbox.mark_sending(ob, 1), 1, Saved("T1"))
  assert outcome == Continue
  assert outbox.is_empty(after)
}

pub fn an_edit_made_while_the_create_is_in_flight_gets_its_base_from_the_ack_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.mark_sending(1)
    |> outbox.record_update(Plans, "p1", title("B"), "unknown-locally")
  assert outbox.pending_count(ob) == 2
  let queued = list.last(ob.entries)
  let assert Ok(update) = queued
  assert update.kind == Update
  assert outbox.needs_base(update)
  let #(after, _) = outbox.handle_response(ob, 1, Saved("T-created"))
  let assert Some(next_entry) = outbox.next(after)
  assert next_entry.base_updated == Some("T-created")
  assert !outbox.needs_base(next_entry)
}

pub fn a_delete_during_an_in_flight_create_is_queued_after_it_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.mark_sending(1)
    |> outbox.record_delete(Plans, "p1", "x")
  assert outbox.pending_count(ob) == 2
  let assert Ok(second) = list.last(ob.entries)
  assert second.fields == fields([outbox.field_bool("deleted", True)])
  assert second.base_updated == None
}

pub fn network_errors_keep_the_entry_and_back_off_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(one, outcome) =
    outbox.handle_response(outbox.mark_sending(ob, 1), 1, NetworkError)
  assert outcome == RetryAfter(2)
  assert head(one).attempts == 1
  assert !head(one).in_flight
  let #(two, outcome) =
    outbox.handle_response(outbox.mark_sending(one, 1), 1, NetworkError)
  assert outcome == RetryAfter(4)
  assert head(two).attempts == 2
}

pub fn backoff_is_capped_test() {
  assert outbox.backoff_seconds(1) == 2
  assert outbox.backoff_seconds(3) == 8
  assert outbox.backoff_seconds(8) == 256
  assert outbox.backoff_seconds(9) == 256
  assert outbox.backoff_seconds(50) == 256
  assert outbox.backoff_seconds(0) == 2
  assert outbox.backoff_seconds(-3) == 2
}

pub fn an_expired_session_loses_nothing_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(after, outcome) =
    outbox.handle_response(outbox.mark_sending(ob, 1), 1, Unauthorized)
  assert outcome == NeedsSignIn
  assert outbox.pending_count(after) == 1
  assert !head(after).in_flight
  assert head(after).attempts == 0
}

pub fn a_conflict_drops_every_entry_for_that_record_only_test() {
  let ob =
    outbox.new()
    |> outbox.record_update(Plans, "p1", title("mine"), "T1")
    |> outbox.record_update(Plans, "p2", title("other"), "T1")
    |> outbox.mark_sending(1)
    |> outbox.record_update(Plans, "p1", title("more"), "T1")
  let #(after, outcome) = outbox.handle_response(ob, 1, Conflict)
  let assert Conflicted(dropped) = outcome
  assert list.map(dropped, fn(e) { e.seq }) == [1, 3]
  assert seqs(after) == [2]
  assert !outbox.has_pending(after, Plans, "p1")
}

pub fn a_create_cannot_conflict_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(after, outcome) =
    outbox.handle_response(outbox.mark_sending(ob, 1), 1, Conflict)
  let assert Failed(_, _) = outcome
  assert outbox.is_empty(after)
}

pub fn a_replayed_create_turns_into_an_update_that_looks_up_its_base_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(after, outcome) =
    outbox.handle_response(outbox.mark_sending(ob, 1), 1, AlreadyExists)
  assert outcome == Continue
  let entry = head(after)
  assert entry.kind == Update
  assert outbox.needs_base(entry)
  let found = outbox.with_base(after, entry.seq, "T-server")
  assert head(found).base_updated == Some("T-server")
  assert !outbox.needs_base(head(found))
}

pub fn an_update_cannot_answer_already_exists_test() {
  let ob = outbox.record_update(outbox.new(), Plans, "p1", title("A"), "T1")
  let #(_, outcome) =
    outbox.handle_response(outbox.mark_sending(ob, 1), 1, AlreadyExists)
  let assert Failed(_, _) = outcome
}

pub fn a_rejected_entry_drops_the_record_and_reports_why_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.record_create(Workouts, "w1", title("W"))
    |> outbox.mark_sending(1)
    |> outbox.record_update(Plans, "p1", title("B"), "x")
  let #(after, outcome) = outbox.handle_response(ob, 1, Rejected("not allowed"))
  let assert Failed(dropped, "not allowed") = outcome
  assert list.map(dropped, fn(e) { e.seq }) == [1, 3]
  assert seqs(after) == [2]
}

pub fn responses_for_unknown_entries_change_nothing_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(after, outcome) = outbox.handle_response(ob, 99, Saved("T"))
  assert after == ob
  assert outcome == Continue
}

pub fn recover_clears_in_flight_flags_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.mark_sending(1)
  assert outbox.next(ob) == None
  assert head(outbox.recover(ob)).id == "p1"
}

pub fn request_bodies_test() {
  let create =
    outbox.record_create(
      outbox.new(),
      Plans,
      "p1",
      fields([
        outbox.field_string("title", "A \"quoted\" plan"),
        outbox.field_int("n", 3),
      ]),
    )
  assert outbox.request_body(head(create))
    == "{\"id\":\"p1\",\"n\":3,\"title\":\"A \\\"quoted\\\" plan\"}"
  let update =
    outbox.record_update(
      outbox.new(),
      Plans,
      "p1",
      fields([
        outbox.field_null("description"),
        outbox.field_bool("deleted", True),
      ]),
      "T1",
    )
  assert outbox.request_body(head(update))
    == "{\"base_updated\":\"T1\",\"deleted\":true,\"description\":null}"
  let unknown_base =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.mark_sending(1)
    |> outbox.record_update(Plans, "p1", title("B"), "x")
  let assert Ok(queued) = list.last(unknown_base.entries)
  assert outbox.request_body(queued) == "{\"title\":\"B\"}"
}

pub fn float_fields_encode_as_json_numbers_test() {
  assert outbox.field_float("distance_m", 10_000.5)
    == #("distance_m", "10000.5")
}

pub fn persistence_round_trips_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A \"q\""))
    |> outbox.mark_sending(1)
    |> outbox.record_update(Plans, "p1", title("B"), "x")
    |> outbox.record_update(
      Plans,
      "p2",
      fields([outbox.field_null("description")]),
      "T9",
    )
  let text = outbox.to_json_string(ob)
  assert outbox.from_json_string(text) == Ok(ob)
  assert outbox.from_json_string(outbox.to_json_string(outbox.new()))
    == Ok(outbox.new())
}

pub fn damaged_persisted_data_is_an_error_test() {
  assert outbox.from_json_string("") == Error(Nil)
  assert outbox.from_json_string("{}") == Error(Nil)
  assert outbox.from_json_string("{\"next_seq\":1,\"entries\":[{\"seq\":1}]}")
    == Error(Nil)
  assert outbox.from_json_string(
      "{\"next_seq\":2,\"entries\":[{\"seq\":1,\"collection\":\"nope\",\"id\":\"a\",\"kind\":\"create\",\"fields\":{},\"base_updated\":null,\"in_flight\":false,\"attempts\":0}]}",
    )
    == Error(Nil)
}

pub fn sequence_numbers_keep_growing_after_entries_leave_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(after, _) =
    outbox.handle_response(outbox.mark_sending(ob, 1), 1, Saved("T"))
  let again = outbox.record_create(after, Plans, "p2", title("B"))
  assert seqs(again) == [2]
}
