//// Replays an outbox against a small fake of the server's behaviour (ADR 0004 and 0011):
//// creates fail with AlreadyExists for known IDs, updates need the current `updated` as base.

import atlas/collection.{Plans, Workouts}
import atlas/outbox.{
  type Entry, type Outbox, type Outcome, type Response, AlreadyExists, Conflict,
  Conflicted, Continue, Create, Entry, NetworkError, Saved,
}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// Server state: record ID to its current `updated` value, plus a counter that makes new values.
type Server {
  Server(records: Dict(String, String), clock: Int, received: List(String))
}

fn new_server(known: List(#(String, String))) -> Server {
  Server(dict.from_list(known), 100, [])
}

fn stamp(server: Server) -> #(Server, String) {
  let updated = "T" <> int.to_string(server.clock + 1)
  #(Server(..server, clock: server.clock + 1), updated)
}

/// The server's answer to one entry. `drop_reply` simulates a lost response: the server applies the
/// entry but the client sees a network error.
fn serve(
  server: Server,
  entry: Entry,
  drop_reply: Bool,
) -> #(Server, Response) {
  let server =
    Server(..server, received: [outbox.request_body(entry), ..server.received])
  case entry.kind {
    Create ->
      case dict.has_key(server.records, entry.id) {
        True -> #(server, AlreadyExists)
        False -> {
          let #(server, updated) = stamp(server)
          let server =
            Server(
              ..server,
              records: dict.insert(server.records, entry.id, updated),
            )
          #(server, reply(drop_reply, updated))
        }
      }
    outbox.Update -> {
      let current = dict.get(server.records, entry.id)
      case current, entry.base_updated {
        Ok(now), Some(base) if now == base -> {
          let #(server, updated) = stamp(server)
          let server =
            Server(
              ..server,
              records: dict.insert(server.records, entry.id, updated),
            )
          #(server, reply(drop_reply, updated))
        }
        Ok(_), Some(_) -> #(server, Conflict)
        _, _ -> #(server, outbox.Rejected("no base"))
      }
    }
  }
}

fn reply(drop_reply: Bool, updated: String) -> Response {
  case drop_reply {
    True -> NetworkError
    False -> Saved(updated)
  }
}

type Run {
  Run(outbox: Outbox, server: Server, outcomes: List(Outcome))
}

/// Sends entries until the outbox is empty or something other than `Continue` happens.
fn drain(run: Run, drop_first_reply: Bool, fuel: Int) -> Run {
  case fuel <= 0 {
    True -> run
    False ->
      case outbox.next(run.outbox) {
        None -> run
        Some(entry) -> {
          // An update with an unknown base looks the record up first, like the real sender.
          let entry = case outbox.needs_base(entry) {
            True ->
              case dict.get(run.server.records, entry.id) {
                Ok(now) -> Entry(..entry, base_updated: Some(now))
                Error(Nil) -> entry
              }
            False -> entry
          }
          let sending = outbox.mark_sending(run.outbox, entry.seq)
          let #(server, response) = serve(run.server, entry, drop_first_reply)
          let #(next_outbox, outcome) =
            outbox.handle_response(sending, entry.seq, response)
          let next_run = Run(next_outbox, server, [outcome, ..run.outcomes])
          case outcome {
            Continue -> drain(next_run, False, fuel - 1)
            outbox.RetryAfter(_) -> drain(next_run, False, fuel - 1)
            _ -> next_run
          }
        }
      }
  }
}

fn title(value: String) -> outbox.Fields {
  dict.from_list([outbox.field_string("title", value)])
}

pub fn offline_work_replays_in_order_and_cancelled_creates_never_reach_the_server_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("10k plan"))
    |> outbox.record_create(Workouts, "w1", title("Easy"))
    |> outbox.record_create(Workouts, "w2", title("Tempo"))
    |> outbox.record_update(Plans, "p1", title("10k plan v2"), "unused")
    |> outbox.record_delete(Workouts, "w1", "unused")
  let run = drain(Run(ob, new_server([]), []), False, 20)
  assert outbox.is_empty(run.outbox)
  assert list.reverse(run.server.received)
    == [
      "{\"id\":\"p1\",\"title\":\"10k plan v2\"}",
      "{\"id\":\"w2\",\"title\":\"Tempo\"}",
    ]
  assert dict.has_key(run.server.records, "p1")
  assert !dict.has_key(run.server.records, "w1")
}

pub fn an_edit_queued_behind_an_in_flight_create_is_sent_with_the_acknowledged_base_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.mark_sending(1)
    |> outbox.record_update(Plans, "p1", title("B"), "unused")
  // The create is acknowledged, then the queued edit goes out with the base from that answer.
  let server = new_server([])
  let #(server, response) = serve(server, list_first(ob), False)
  let #(ob, _) = outbox.handle_response(ob, 1, response)
  let run = drain(Run(ob, server, []), False, 10)
  assert outbox.is_empty(run.outbox)
  assert dict.get(run.server.records, "p1") == Ok("T102")
}

fn list_first(ob: Outbox) -> Entry {
  let assert [first, ..] = ob.entries
  first
}

pub fn a_lost_reply_leads_to_a_replay_that_does_not_duplicate_test() {
  let ob = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  // The server creates the record, but the reply is lost.
  let first = drain(Run(ob, new_server([]), []), True, 1)
  assert outbox.pending_count(first.outbox) == 1
  // After a restart the app recovers the outbox and tries again.
  let again =
    drain(Run(outbox.recover(first.outbox), first.server, []), False, 10)
  assert outbox.is_empty(again.outbox)
  assert dict.size(again.server.records) == 1
}

pub fn an_edit_based_on_a_stale_record_ends_in_a_conflict_with_the_edit_handed_back_test() {
  // The server's record moved on to T150 while this device was offline.
  let ob =
    outbox.new()
    |> outbox.record_update(Plans, "p1", title("from phone"), "T100")
    |> outbox.record_create(Plans, "p2", title("unrelated"))
  let run = drain(Run(ob, new_server([#("p1", "T150")]), []), False, 10)
  let assert [Conflicted([edit]), ..] = run.outcomes
  assert edit.fields == title("from phone")
  assert dict.get(run.server.records, "p1") == Ok("T150")
  // The unrelated entry is still queued and goes out once the caller has dealt with the conflict.
  assert outbox.pending_count(run.outbox) == 1
  let done = drain(Run(run.outbox, run.server, []), False, 10)
  assert outbox.is_empty(done.outbox)
  assert dict.has_key(done.server.records, "p2")
}
