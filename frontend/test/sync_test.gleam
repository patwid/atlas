//// The sync engine against a small fake PocketBase (see ADR 0004, 0011, 0016 and 0017).

import atlas/api.{type Request, Get, Patch, Post}
import atlas/collection.{type Collection, Activities, Matches, Plans, Workouts}
import atlas/cursor.{Cursor}
import atlas/date.{Date}
import atlas/outbox
import atlas/sync.{
  type Command, type Event, type Sync, Apply, CheckStart, Conflicts, Finished,
  PullFailed, Reconcile, Rejections, Responded, RetryIn, SaveCursor, SaveOutbox,
  Send, SessionRefreshed, SignInRequired, Started, Tell,
}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import gleam/uri

// THE FAKE SERVER ---------------------------------------------------------------------------------

type Rec {
  Rec(
    collection: String,
    id: String,
    updated: String,
    deleted: Bool,
    title: String,
  )
}

type Server {
  Server(
    records: Dict(String, Rec),
    clock: Int,
    /// How many more requests see a valid token. Afterwards the server treats the caller as anonymous.
    valid_requests: Int,
    requests: List(Request),
    /// A collection whose list answers 400.
    broken: String,
    page_size: Int,
  )
}

/// How many collections a run pulls and a sweep reconciles.
fn collections() -> Int {
  list.length(collection.all)
}

fn server(records: List(Rec)) -> Server {
  Server(
    records: dict.from_list(
      list.map(records, fn(r) { #(r.collection <> "/" <> r.id, r) }),
    ),
    clock: 500,
    valid_requests: 1_000_000,
    requests: [],
    broken: "",
    page_size: 2,
  )
}

fn rec(collection: String, id: String, stamp: Int, title: String) -> Rec {
  Rec(collection, id, stamp_text(stamp), False, title)
}

fn stamp_text(n: Int) -> String {
  "2026-10-06 08:00:00." <> string.pad_start(int.to_string(n), 3, "0") <> "Z"
}

fn rec_json(r: Rec) -> String {
  "{\"id\":\""
  <> r.id
  <> "\",\"updated\":\""
  <> r.updated
  <> "\",\"deleted\":"
  <> case r.deleted {
    True -> "true"
    False -> "false"
  }
  <> ",\"title\":\""
  <> r.title
  <> "\"}"
}

type Body {
  Body(id: String, base: String, title: String, deleted: Option(Bool))
}

fn read_body(text: String) -> Body {
  let decoder = {
    use id <- decode.optional_field("id", "", decode.string)
    use base <- decode.optional_field("base_updated", "", decode.string)
    use title <- decode.optional_field("title", "", decode.string)
    use deleted <- decode.optional_field(
      "deleted",
      None,
      decode.optional(decode.bool),
    )
    decode.success(Body(id, base, title, deleted))
  }
  case json.parse(text, decoder) {
    Ok(body) -> body
    Error(_) -> Body("", "", "", None)
  }
}

fn query_of(path: String) -> #(String, Dict(String, String)) {
  case string.split_once(path, "?") {
    Error(Nil) -> #(path, dict.new())
    Ok(#(before, query)) -> #(
      before,
      string.split(query, "&")
        |> list.filter_map(fn(pair) {
          case string.split_once(pair, "=") {
            Ok(#(k, v)) ->
              case uri.percent_decode(v) {
                Ok(decoded) -> Ok(#(k, decoded))
                Error(Nil) -> Ok(#(k, v))
              }
            Error(Nil) -> Error(Nil)
          }
        })
        |> dict.from_list,
    )
  }
}

const bad_token =
  "{\"data\":{},\"message\":\"The request requires valid record authorization token.\",\"status\":401}"

fn handle(server: Server, request: Request) -> #(Server, Int, String) {
  let valid = server.valid_requests > 0
  let server =
    Server(..server, valid_requests: server.valid_requests - 1, requests: [
      request,
      ..server.requests
    ])
  let #(path, query) = query_of(request.path)
  let body = read_body(option.unwrap(request.body, ""))
  let wants_ids = dict.get(query, "fields") == Ok("id")
  case request.method, string.split(path, "/") {
    Post, ["", "api", "collections", "users", "auth-refresh"] ->
      case valid {
        True -> #(
          server,
          200,
          "{\"token\":\"fresh.tok.en\",\"record\":{\"id\":\"u1\"}}",
        )
        False -> #(server, 401, bad_token)
      }

    Post, ["", "api", "collections", c, "records"] ->
      case
        valid,
        dict.has_key(server.records, c <> "/" <> body.id),
        body.title
      {
        False, _, _ -> #(
          server,
          400,
          "{\"data\":{},\"message\":\"Failed to create record.\",\"status\":400}",
        )
        True, True, _ -> #(
          server,
          400,
          "{\"data\":{\"id\":{\"code\":\"validation_not_unique\",\"message\":\"Value must be unique.\"}},\"message\":\"Failed to create record.\",\"status\":400}",
        )
        True, False, "REJECT" -> #(
          server,
          400,
          "{\"data\":{},\"message\":\"Failed to create record.\",\"status\":400}",
        )
        True, False, _ -> {
          let clock = server.clock + 1
          let r = Rec(c, body.id, stamp_text(clock), False, body.title)
          #(
            Server(
              ..server,
              clock: clock,
              records: dict.insert(server.records, c <> "/" <> body.id, r),
            ),
            200,
            rec_json(r),
          )
        }
      }

    Patch, ["", "api", "collections", c, "records", id] ->
      case valid, dict.get(server.records, c <> "/" <> id) {
        True, Ok(current) ->
          case current.updated == body.base {
            False -> #(
              server,
              409,
              "{\"data\":{},\"message\":\"The record was changed since base_updated.\",\"status\":409}",
            )
            True -> {
              let clock = server.clock + 1
              let r =
                Rec(
                  ..current,
                  updated: stamp_text(clock),
                  title: case body.title {
                    "" -> current.title
                    t -> t
                  },
                  deleted: option.unwrap(body.deleted, current.deleted),
                )
              #(
                Server(
                  ..server,
                  clock: clock,
                  records: dict.insert(server.records, c <> "/" <> id, r),
                ),
                200,
                rec_json(r),
              )
            }
          }
        _, _ -> #(
          server,
          404,
          "{\"data\":{},\"message\":\"The requested resource wasn't found.\",\"status\":404}",
        )
      }

    Get, ["", "api", "collections", c, "records", id] ->
      case valid, dict.get(server.records, c <> "/" <> id) {
        True, Ok(r) -> #(server, 200, rec_json(r))
        _, _ -> #(
          server,
          404,
          "{\"data\":{},\"message\":\"The requested resource wasn't found.\",\"status\":404}",
        )
      }

    Get, ["", "api", "collections", c, "records"] if wants_ids -> {
      // The membership sweep: only IDs, in ID order, after a given ID (ADR 0030).
      let after = case dict.get(query, "filter") {
        Ok(f) ->
          case string.split(f, "\"") {
            [_, value, _] -> value
            _ -> ""
          }
        Error(Nil) -> ""
      }
      let per_page = case dict.get(query, "perPage") {
        Ok(p) -> option.unwrap(option.from_result(int.parse(p)), 30)
        Error(Nil) -> 30
      }
      let ids = case valid {
        // An invalid token is an anonymous caller who can read nothing.
        False -> []
        True ->
          dict.values(server.records)
          |> list.filter(fn(r) {
            r.collection == c
            && { after == "" || string.compare(r.id, after) == order.Gt }
          })
          |> list.map(fn(r) { r.id })
          |> list.sort(string.compare)
          |> list.take(per_page)
      }
      #(
        server,
        200,
        "{\"items\":["
          <> string.join(
          list.map(ids, fn(id) { "{\"id\":\"" <> id <> "\"}" }),
          ",",
        )
          <> "],\"page\":1,\"perPage\":"
          <> int.to_string(per_page)
          <> ",\"totalItems\":-1,\"totalPages\":-1}",
      )
    }

    Get, ["", "api", "collections", c, "records"] ->
      case c == server.broken {
        True -> #(
          server,
          400,
          "{\"message\":\"Something went wrong while processing your request.\"}",
        )
        False -> {
          let since = case dict.get(query, "filter") {
            Ok(f) ->
              case string.split(f, "\"") {
                [_, value, _] -> value
                _ -> ""
              }
            Error(Nil) -> ""
          }
          let matching = case valid {
            // An invalid token is an anonymous caller who owns nothing.
            False -> []
            True ->
              dict.values(server.records)
              |> list.filter(fn(r) {
                r.collection == c
                && string.compare(r.updated, since) != order.Lt
              })
              |> list.sort(fn(a, b) {
                string.compare(a.updated <> a.id, b.updated <> b.id)
              })
          }
          let page = case dict.get(query, "page") {
            Ok(p) -> option.unwrap(option.from_result(int.parse(p)), 1)
            Error(Nil) -> 1
          }
          let total = list.length(matching)
          let pages = { total + server.page_size - 1 } / server.page_size
          let items =
            matching
            |> list.drop({ page - 1 } * server.page_size)
            |> list.take(server.page_size)
          #(
            server,
            200,
            "{\"items\":["
              <> string.join(list.map(items, rec_json), ",")
              <> "],\"page\":"
              <> int.to_string(page)
              <> ",\"perPage\":200,\"totalItems\":"
              <> int.to_string(total)
              <> ",\"totalPages\":"
              <> int.to_string(pages)
              <> "}",
          )
        }
      }

    _, _ -> #(server, 404, "")
  }
}

// THE DRIVER --------------------------------------------------------------------------------------

type World {
  World(sync: Sync, server: Server, log: List(Command))
}

fn world(
  box: outbox.Outbox,
  cursors: List(#(Collection, cursor.Cursor)),
  s: Server,
) -> World {
  World(sync.new(box, cursors, recently_swept), s, [])
}

/// The time the tests start runs at, and a sweep time shortly before it: no sweep is due unless a test says so.
const now = 1_000_000

const recently_swept = Some(999_900)

fn today() -> date.Date {
  Date(2026, 10, 6)
}

fn started() -> Event {
  Started(today(), False, now)
}

fn run(w: World, event: Event) -> World {
  let #(next, commands) = sync.update(w.sync, event)
  exec(World(..w, sync: next), commands, 200)
}

fn exec(w: World, commands: List(Command), fuel: Int) -> World {
  case commands, fuel {
    _, 0 -> w
    [], _ -> w
    [Send(request, tag), ..rest], _ -> {
      let #(server, status, body) = handle(w.server, request)
      let w = run(World(..w, server: server), Responded(tag, status, body))
      exec(w, rest, fuel - 1)
    }
    [other, ..rest], _ ->
      exec(World(..w, log: [other, ..w.log]), rest, fuel - 1)
  }
}

fn log(w: World) -> List(Command) {
  list.reverse(w.log)
}

fn title(value: String) -> outbox.Fields {
  dict.from_list([outbox.field_string("title", value)])
}

fn ids(records: List(Dynamic)) -> List(String) {
  list.filter_map(records, fn(record) {
    case api.record_meta(record) {
      Ok(meta) -> Ok(meta.id)
      Error(Nil) -> Error(Nil)
    }
  })
}

fn applied(w: World, c: Collection) -> List(List(String)) {
  list.filter_map(log(w), fn(command) {
    case command {
      Apply(collection, records) if collection == c -> Ok(ids(records))
      _ -> Error(Nil)
    }
  })
}

fn notices(w: World) -> List(sync.Notice) {
  list.filter_map(log(w), fn(command) {
    case command {
      Tell(notice) -> Ok(notice)
      _ -> Error(Nil)
    }
  })
}

fn saved_cursors(w: World) -> List(Collection) {
  list.filter_map(log(w), fn(command) {
    case command {
      SaveCursor(c, _) -> Ok(c)
      _ -> Error(Nil)
    }
  })
}

fn reconciled(w: World) -> List(#(Collection, List(String))) {
  list.filter_map(log(w), fn(command) {
    case command {
      Reconcile(c, keep) -> Ok(#(c, keep))
      _ -> Error(Nil)
    }
  })
}

fn paths(w: World) -> List(String) {
  list.reverse(w.server.requests) |> list.map(fn(r) { r.path })
}

fn is_finished(w: World) -> Bool {
  list.contains(notices(w), Finished)
}

// TESTS -------------------------------------------------------------------------------------------

pub fn a_first_run_checks_the_session_pushes_then_pulls_everything_test() {
  let s =
    server([
      rec("plans", "a", 100, "A"),
      rec("plans", "b", 110, "B"),
      rec("workouts", "w1", 120, "W"),
    ])
  let box = outbox.record_create(outbox.new(), Plans, "new1", title("New plan"))
  let w = run(world(box, [], s), started())
  // Order of requests: session check, the create, then one list per collection, then the final check.
  let requests = paths(w)
  assert list.take(requests, 2)
    == ["/api/collections/users/auth-refresh", "/api/collections/plans/records"]
  assert list.last(requests) == Ok("/api/collections/users/auth-refresh")
  assert dict.has_key(w.server.records, "plans/new1")
  // The server's answer to the create is stored first, then the pulled plans (which include it again).
  assert applied(w, Plans) == [["new1"], ["a", "b"], ["new1"]]
  assert applied(w, Workouts) == [["w1"]]
  // Everything was a full resync, so every collection is reconciled and gets a cursor.
  assert list.length(reconciled(w)) == collections()
  assert list.length(saved_cursors(w)) == collections()
  assert is_finished(w)
  assert !sync.is_busy(w.sync)
  let assert [SessionRefreshed(_), ..] = notices(w)
  assert outbox.is_empty(sync.outbox(w.sync))
}

pub fn the_outbox_is_saved_after_every_answer_test() {
  let box =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.record_create(Plans, "p2", title("B"))
  let w = run(world(box, [], server([])), started())
  let saved =
    list.filter_map(log(w), fn(c) {
      case c {
        SaveOutbox(o) -> Ok(outbox.pending_count(o))
        _ -> Error(Nil)
      }
    })
  assert saved == [1, 0]
}

pub fn pages_are_pulled_until_the_last_one_test() {
  let s =
    server(
      list.map([1, 2, 3, 4, 5], fn(n) {
        rec("plans", "p" <> int.to_string(n), 100 + n, "t")
      }),
    )
  let w = run(world(outbox.new(), [], s), started())
  assert applied(w, Plans) == [["p1", "p2"], ["p3", "p4"], ["p5"]]
  assert list.any(paths(w), fn(p) { string.contains(p, "plans/records?page=3") })
}

pub fn later_runs_pull_only_changes_since_the_cursor_test() {
  let s =
    server([
      rec("plans", "old", 100, "x"),
      rec("plans", "edge", 200, "x"),
      rec("plans", "new", 300, "x"),
    ])
  let c = Cursor(stamp_text(200), Date(2026, 10, 5))
  let w = run(world(outbox.new(), [#(Plans, c)], s), started())
  // `>=`: the record at the cursor itself is fetched again, which is harmless.
  assert applied(w, Plans) == [["edge", "new"]]
  assert !list.any(reconciled(w), fn(r) { r.0 == Plans })
  let assert Ok(SaveCursor(_, saved)) =
    list.find(log(w), fn(command) {
      case command {
        SaveCursor(Plans, _) -> True
        _ -> False
      }
    })
  assert saved == Cursor(stamp_text(300), today())
}

pub fn a_cursor_older_than_the_limit_forces_a_full_resync_test() {
  let s = server([rec("plans", "a", 100, "x")])
  let stale = Cursor(stamp_text(100), Date(2026, 6, 1))
  let w = run(world(outbox.new(), [#(Plans, stale)], s), started())
  assert list.contains(reconciled(w), #(Plans, ["a"]))
}

pub fn a_collection_the_server_refuses_is_reported_and_skipped_test() {
  let s = Server(..server([rec("workouts", "w1", 100, "x")]), broken: "plans")
  let w = run(world(outbox.new(), [], s), started())
  assert list.contains(notices(w), PullFailed(Plans, 400))
  assert applied(w, Workouts) == [["w1"]]
  assert !list.contains(saved_cursors(w), Plans)
  assert list.contains(saved_cursors(w), Workouts)
  assert is_finished(w)
}

pub fn a_stale_edit_becomes_a_conflict_and_the_run_carries_on_test() {
  let s = server([rec("plans", "a", 200, "server version")])
  let box =
    outbox.new()
    |> outbox.record_update(Plans, "a", title("my edit"), stamp_text(100))
    |> outbox.record_create(Plans, "b", title("unrelated"))
  let w = run(world(box, [], s), started())
  let assert Ok(Conflicts([dropped])) =
    list.find(notices(w), fn(n) {
      case n {
        Conflicts(_) -> True
        _ -> False
      }
    })
  assert dropped.id == "a"
  assert dropped.fields == title("my edit")
  assert dict.has_key(w.server.records, "plans/b")
  let assert Ok(untouched) = dict.get(w.server.records, "plans/a")
  assert untouched.title == "server version"
  assert is_finished(w)
}

pub fn a_rejection_is_only_final_when_the_session_is_valid_test() {
  let box = outbox.record_create(outbox.new(), Plans, "p1", title("REJECT"))
  let w = run(world(box, [], server([])), started())
  let assert Ok(Rejections([entry], reason)) =
    list.find(notices(w), fn(n) {
      case n {
        Rejections(_, _) -> True
        _ -> False
      }
    })
  assert entry.id == "p1"
  assert reason == "Failed to create record."
  // The 400 was followed by a session check before the entry was dropped.
  let requests = paths(w)
  assert list.take(requests, 3)
    == [
      "/api/collections/users/auth-refresh",
      "/api/collections/plans/records",
      "/api/collections/users/auth-refresh",
    ]
  assert is_finished(w)
}

pub fn a_token_revoked_during_the_run_loses_no_edits_test() {
  // The start check passes, then the token stops being valid: the create is refused like a rejection.
  let s = Server(..server([]), valid_requests: 1)
  let box = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let w = run(world(box, [], s), started())
  assert list.contains(notices(w), SignInRequired)
  assert !list.any(notices(w), fn(n) {
    case n {
      Rejections(_, _) -> True
      _ -> False
    }
  })
  assert outbox.pending_count(sync.outbox(w.sync)) == 1
  assert !sync.is_busy(w.sync)
  assert !is_finished(w)
}

pub fn a_token_revoked_before_the_pull_never_moves_cursors_or_deletes_data_test() {
  // Valid for the start check only. The lists then come back empty with status 200.
  let s = Server(..server([rec("plans", "a", 100, "x")]), valid_requests: 1)
  let c = Cursor(stamp_text(100), Date(2026, 10, 5))
  let incremental = run(world(outbox.new(), [#(Plans, c)], s), started())
  assert saved_cursors(incremental) == []
  assert reconciled(incremental) == []
  assert list.contains(notices(incremental), SignInRequired)
  let full = run(world(outbox.new(), [], s), started())
  assert reconciled(full) == []
  assert saved_cursors(full) == []
  assert list.contains(notices(full), SignInRequired)
}

pub fn an_expired_token_asks_for_sign_in_without_sending_anything_test() {
  let box = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let w = run(world(box, [], server([])), Started(today(), True, now))
  assert w.server.requests == []
  assert notices(w) == [SignInRequired]
  assert outbox.pending_count(sync.outbox(w.sync)) == 1
}

pub fn a_failed_session_check_at_the_start_waits_and_can_be_retried_test() {
  let w = run(world(outbox.new(), [], server([])), started())
  assert is_finished(w)
  let #(waiting, commands) =
    sync.update(sync.new(outbox.new(), [], recently_swept), started())
  assert commands == [Send(api.refresh(), CheckStart)]
  let #(waiting, commands) = sync.update(waiting, Responded(CheckStart, 0, ""))
  assert commands == [RetryIn(2)]
  assert !sync.is_busy(waiting)
  // The next failure waits longer.
  let #(waiting, _) = sync.update(waiting, started())
  let #(_, commands) = sync.update(waiting, Responded(CheckStart, 503, ""))
  assert commands == [RetryIn(4)]
}

pub fn a_server_error_while_pushing_keeps_the_entry_and_retries_test() {
  let box = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(s0, _) = sync.update(sync.new(box, [], recently_swept), started())
  let #(s1, commands) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  let assert [Tell(SessionRefreshed(_)), Send(_, tag)] = commands
  let #(s2, commands) = sync.update(s1, Responded(tag, 503, ""))
  assert commands == [SaveOutbox(sync.outbox(s2)), RetryIn(2)]
  assert outbox.pending_count(sync.outbox(s2)) == 1
  // Starting again sends it once more.
  let #(_, commands) = sync.update(s2, started())
  assert commands == [Send(api.refresh(), CheckStart)]
}

pub fn a_replayed_create_looks_up_the_base_and_becomes_an_update_test() {
  let s = server([rec("plans", "p1", 100, "old")])
  let box =
    outbox.record_create(outbox.new(), Plans, "p1", title("edited offline"))
  let w = run(world(box, [], s), started())
  let assert Ok(now) = dict.get(w.server.records, "plans/p1")
  assert now.title == "edited offline"
  assert outbox.is_empty(sync.outbox(w.sync))
  let requests =
    list.reverse(w.server.requests) |> list.map(fn(r) { #(r.method, r.path) })
  assert list.take(requests, 4)
    == [
      #(Post, "/api/collections/users/auth-refresh"),
      #(Post, "/api/collections/plans/records"),
      #(Get, "/api/collections/plans/records/p1"),
      #(Patch, "/api/collections/plans/records/p1"),
    ]
  assert is_finished(w)
}

pub fn a_record_with_unsent_local_edits_is_not_overwritten_by_a_pull_test() {
  let #(s0, _) =
    sync.update(sync.new(outbox.new(), [], recently_swept), started())
  let #(s1, _) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  // Coach grants come first in the pull; once they are in, the plans page is the one on the way.
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  let #(s1, _) =
    sync.update(s1, Responded(sync.Pull(collection.CoachGrants, 1), 200, empty))
  // The user edits plan a while its page is on the way.
  let s2 =
    sync.change_outbox(s1, fn(box) {
      outbox.record_update(box, Plans, "a", title("local"), stamp_text(100))
    })
  let page =
    "{\"items\":[{\"id\":\"a\",\"updated\":\""
    <> stamp_text(100)
    <> "\",\"deleted\":false},{\"id\":\"b\",\"updated\":\""
    <> stamp_text(110)
    <> "\",\"deleted\":false}],\"page\":1,\"perPage\":200,\"totalItems\":2,\"totalPages\":1}"
  let #(_, commands) =
    sync.update(s2, Responded(sync.Pull(Plans, 1), 200, page))
  let assert [Apply(Plans, records), ..] = commands
  assert ids(records) == ["b"]
}

pub fn local_writes_made_during_the_pull_are_pushed_before_the_run_ends_test() {
  let #(s0, _) =
    sync.update(sync.new(outbox.new(), [], recently_swept), started())
  let #(s1, _) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  // Nothing to push, so the first list request is out. Jump to the end of the pull by answering each one.
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  let s2 = answer_all_lists(s1, empty, collections())
  let s3 =
    sync.change_outbox(s2, fn(box) {
      outbox.record_create(box, Plans, "late", title("written during the pull"))
    })
  let #(_, commands) =
    sync.update(s3, Responded(sync.VerifyForCommit, 200, "{}"))
  let assert [_, ..] = commands
  assert list.any(commands, fn(command) {
    case command {
      Send(request, sync.Push(_)) -> request.method == Post
      _ -> False
    }
  })
  assert !list.contains(commands, Tell(Finished))
}

fn answer_all_lists(state: Sync, body: String, count: Int) -> Sync {
  case count {
    0 -> state
    _ -> {
      let assert Ok(c) =
        list.first(list.drop(collection.all, collections() - count))
      let #(next, _) = sync.update(state, Responded(sync.Pull(c, 1), 200, body))
      answer_all_lists(next, body, count - 1)
    }
  }
}

pub fn started_while_busy_is_ignored_and_stale_answers_do_nothing_test() {
  let #(busy, _) =
    sync.update(sync.new(outbox.new(), [], recently_swept), started())
  assert sync.is_busy(busy)
  let #(same, commands) = sync.update(busy, started())
  assert commands == []
  assert sync.is_busy(same)
  let #(_, commands) =
    sync.update(
      sync.new(outbox.new(), [], recently_swept),
      Responded(sync.Push(99), 200, "{}"),
    )
  assert commands == []
  let #(_, commands) =
    sync.update(busy, Responded(sync.Pull(Matches, 1), 200, "{}"))
  assert commands == []
}

pub fn activities_pulled_from_the_server_are_applied_test() {
  let s = server([Rec("activities", "x1", stamp_text(100), False, "run")])
  let w = run(world(outbox.new(), [], s), started())
  assert applied(w, Activities) == [["x1"]]
}

pub fn the_servers_answer_to_a_save_replaces_the_local_copy_test() {
  let box = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let w = run(world(box, [], server([])), started())
  let assert [first, ..] = applied(w, Plans)
  assert first == ["p1"]
}

pub fn the_answer_is_not_applied_over_later_queued_edits_test() {
  // The create is in flight when the user edits again; the edit is queued behind it.
  let box = outbox.record_create(outbox.new(), Plans, "p1", title("A"))
  let #(s0, _) = sync.update(sync.new(box, [], recently_swept), started())
  let #(s1, commands) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  let assert [Tell(SessionRefreshed(_)), Send(_, tag)] = commands
  let s2 =
    sync.change_outbox(s1, fn(b) {
      outbox.record_update(b, Plans, "p1", title("B"), "x")
    })
  let created =
    "{\"id\":\"p1\",\"updated\":\""
    <> stamp_text(501)
    <> "\",\"deleted\":false,\"title\":\"A\"}"
  let #(_, commands) = sync.update(s2, Responded(tag, 200, created))
  assert !list.any(commands, fn(c) {
    case c {
      Apply(_, _) -> True
      _ -> False
    }
  })
}

pub fn a_start_requested_during_a_run_makes_another_run_follow_it_test() {
  let #(s0, _) =
    sync.update(sync.new(outbox.new(), [], recently_swept), started())
  // The request comes while the first run is going on: nothing is sent for it...
  let #(s1, commands) = sync.update(s0, started())
  assert commands == []
  assert sync.is_busy(s1)
  // ...but when the first run ends, a new one begins with a session check.
  let #(s2, _) = sync.update(s1, Responded(CheckStart, 200, "{}"))
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  let s3 = answer_all_lists(s2, empty, collections())
  let #(s4, commands) =
    sync.update(s3, Responded(sync.VerifyForCommit, 200, "{}"))
  assert list.contains(commands, Tell(Finished))
  assert list.contains(commands, Send(api.refresh(), CheckStart))
  assert sync.is_busy(s4)
}

pub fn without_a_request_during_the_run_it_just_ends_test() {
  let #(s0, _) =
    sync.update(sync.new(outbox.new(), [], recently_swept), started())
  let #(s1, _) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  let s2 = answer_all_lists(s1, empty, collections())
  let #(s3, commands) =
    sync.update(s2, Responded(sync.VerifyForCommit, 200, "{}"))
  assert list.contains(commands, Tell(Finished))
  assert !list.contains(commands, Send(api.refresh(), CheckStart))
  assert !sync.is_busy(s3)
}

pub fn many_requests_during_one_run_cause_only_one_more_run_test() {
  let #(s0, _) =
    sync.update(sync.new(outbox.new(), [], recently_swept), started())
  let #(s1, _) = sync.update(s0, started())
  let #(s2, _) = sync.update(s1, started())
  let #(s3, _) = sync.update(s2, Responded(CheckStart, 200, "{}"))
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  let s4 = answer_all_lists(s3, empty, collections())
  let #(s5, _) = sync.update(s4, Responded(sync.VerifyForCommit, 200, "{}"))
  // The second run ends like any other, and no third one follows.
  let #(s6, _) = sync.update(s5, Responded(CheckStart, 200, "{}"))
  let s7 = answer_all_lists(s6, empty, collections())
  let #(s8, commands) =
    sync.update(s7, Responded(sync.VerifyForCommit, 200, "{}"))
  assert list.contains(commands, Tell(Finished))
  assert !sync.is_busy(s8)
}

pub fn the_engine_remembers_the_newest_updated_it_has_seen_test() {
  let box = outbox.record_create(outbox.new(), Plans, "new1", title("A"))
  let w =
    run(world(box, [], server([rec("plans", "old1", 100, "x")])), started())
  // After the create is acknowledged, the engine knows the record's new `updated`...
  let known = sync.freshest_base(w.sync, Plans, "new1", "")
  assert known != ""
  assert known
    == {
      let assert Ok(r) = dict.get(w.server.records, "plans/new1")
      r.updated
    }
  // ...and from a pull, the one of a record it never wrote.
  assert sync.freshest_base(w.sync, Plans, "old1", "") == stamp_text(100)
}

pub fn a_newer_value_from_the_caller_wins_and_unknown_records_use_it_test() {
  let box = outbox.record_create(outbox.new(), Plans, "new1", title("A"))
  let w = run(world(box, [], server([])), started())
  assert sync.freshest_base(w.sync, Plans, "new1", "9999-12-31 00:00:00.000Z")
    == "9999-12-31 00:00:00.000Z"
  assert sync.freshest_base(w.sync, Plans, "never-seen", "T-given") == "T-given"
  assert sync.freshest_base(
      sync.new(outbox.new(), [], recently_swept),
      Plans,
      "x",
      "T0",
    )
    == "T0"
}

// THE MEMBERSHIP SWEEP (ADR 0030) -----------------------------------------------------------------

fn every_collection_incremental() -> List(#(Collection, cursor.Cursor)) {
  list.map(collection.all, fn(c) {
    #(c, Cursor(stamp_text(1), Date(2026, 10, 5)))
  })
}

fn id_requests(w: World) -> List(String) {
  list.filter(paths(w), fn(p) { string.contains(p, "fields=id") })
}

fn many(count: Int) -> List(Rec) {
  list.index_map(list.repeat(Nil, count), fn(_, i) {
    rec("plans", "p" <> string.pad_start(int.to_string(i), 4, "0"), 100, "t")
  })
}

pub fn a_due_sweep_lists_the_readable_ids_and_reconciles_every_collection_test() {
  let s =
    server([
      rec("plans", "a", 100, "x"),
      rec("plans", "b", 110, "x"),
      rec("workouts", "w1", 120, "x"),
    ])
  let w =
    run(
      World(sync.new(outbox.new(), every_collection_incremental(), None), s, []),
      started(),
    )
  assert list.contains(reconciled(w), #(Plans, ["a", "b"]))
  assert list.contains(reconciled(w), #(Workouts, ["w1"]))
  assert list.contains(reconciled(w), #(Matches, []))
  assert list.length(reconciled(w)) == collections()
  assert list.length(id_requests(w)) == collections()
  assert list.contains(log(w), sync.SaveSweep(now))
  assert is_finished(w)
}

pub fn the_removal_waits_until_the_session_was_confirmed_at_the_end_test() {
  let s = server([rec("plans", "a", 100, "x")])
  let w =
    run(
      World(sync.new(outbox.new(), every_collection_incremental(), None), s, []),
      started(),
    )
  let commands = log(w)
  // The reconciles come after the pull's own work and before the sweep is recorded.
  let position = fn(target) { list_index(commands, target) }
  assert position(sync.SaveSweep(now)) > position(Reconcile(Plans, ["a"]))
}

fn list_index(items: List(a), target: a) -> Int {
  case items {
    [] -> -1
    [first, ..rest] ->
      case first == target {
        True -> 0
        False ->
          case list_index(rest, target) {
            -1 -> -1
            found -> found + 1
          }
      }
  }
}

pub fn no_sweep_when_one_ran_recently_test() {
  let s = server([rec("plans", "a", 100, "x")])
  let w =
    run(
      World(
        sync.new(outbox.new(), every_collection_incremental(), Some(now - 100)),
        s,
        [],
      ),
      started(),
    )
  assert id_requests(w) == []
  assert reconciled(w) == []
  assert !list.contains(log(w), sync.SaveSweep(now))
  assert is_finished(w)
}

pub fn the_sweep_is_due_exactly_after_the_interval_test() {
  let at = fn(seconds_ago) {
    let w =
      run(
        World(
          sync.new(
            outbox.new(),
            every_collection_incremental(),
            Some(now - seconds_ago),
          ),
          server([]),
          [],
        ),
        started(),
      )
    id_requests(w) != []
  }
  assert !at(599)
  assert at(600)
  assert at(100_000)
}

pub fn a_new_device_that_resyncs_everything_does_not_sweep_as_well_test() {
  // Without cursors every collection is a full resync, which is complete by itself.
  let w =
    run(
      World(
        sync.new(outbox.new(), [], None),
        server([rec("plans", "a", 100, "x")]),
        [],
      ),
      started(),
    )
  assert id_requests(w) == []
  assert list.length(reconciled(w)) == collections()
  assert !list.contains(log(w), sync.SaveSweep(now))
}

pub fn only_the_collections_with_a_cursor_are_swept_test() {
  let cursors = [#(Plans, Cursor(stamp_text(1), Date(2026, 10, 5)))]
  let w =
    run(
      World(
        sync.new(outbox.new(), cursors, None),
        server([rec("plans", "a", 100, "x")]),
        [],
      ),
      started(),
    )
  assert list.length(id_requests(w)) == 1
  assert list.all(id_requests(w), fn(p) { string.contains(p, "/plans/") })
}

pub fn a_token_revoked_during_the_run_removes_nothing_test() {
  // The start check passes; after that the server answers as if to an anonymous user: empty lists, status 200.
  // Taken at face value the sweep would conclude that everything is gone.
  let s = Server(..server([rec("plans", "a", 100, "x")]), valid_requests: 1)
  let w =
    run(
      World(sync.new(outbox.new(), every_collection_incremental(), None), s, []),
      started(),
    )
  assert reconciled(w) == []
  assert !list.contains(log(w), sync.SaveSweep(now))
  assert list.contains(notices(w), SignInRequired)
}

pub fn a_sweep_makes_the_next_run_skip_it_test() {
  let s = server([rec("plans", "a", 100, "x")])
  let first =
    run(
      World(sync.new(outbox.new(), every_collection_incremental(), None), s, []),
      started(),
    )
  let count = list.length(id_requests(first))
  assert count == collections()
  let second = run(first, started())
  assert list.length(id_requests(second)) == count
}

pub fn a_failed_confirmation_does_not_count_as_a_sweep_test() {
  let s = Server(..server([rec("plans", "a", 100, "x")]), valid_requests: 1)
  let failed =
    run(
      World(sync.new(outbox.new(), every_collection_incremental(), None), s, []),
      started(),
    )
  // Signed in again with a working token: the sweep is still due and now succeeds.
  let again =
    run(
      World(
        ..failed,
        server: Server(..failed.server, valid_requests: 1_000_000),
        log: [],
      ),
      started(),
    )
  assert list.length(reconciled(again)) == collections()
}

pub fn many_ids_are_walked_in_pages_of_five_hundred_test() {
  let w =
    run(
      World(
        sync.new(
          outbox.new(),
          [#(Plans, Cursor(stamp_text(1), Date(2026, 10, 5)))],
          None,
        ),
        Server(..server(many(1200)), page_size: 1000),
        [],
      ),
      started(),
    )
  let assert Ok(#(_, ids)) = list.find(reconciled(w), fn(r) { r.0 == Plans })
  assert list.length(ids) == 1200
  assert ids == list.sort(ids, string.compare)
  assert list.length(list.unique(ids)) == 1200
  // 500 + 500 + 200: the short page ends the walk.
  assert list.length(id_requests(w)) == 3
}

pub fn exactly_one_full_page_needs_one_more_request_to_be_sure_test() {
  let w =
    run(
      World(
        sync.new(
          outbox.new(),
          [#(Plans, Cursor(stamp_text(1), Date(2026, 10, 5)))],
          None,
        ),
        Server(..server(many(500)), page_size: 1000),
        [],
      ),
      started(),
    )
  let assert Ok(#(_, ids)) = list.find(reconciled(w), fn(r) { r.0 == Plans })
  assert list.length(ids) == 500
  assert list.length(id_requests(w)) == 2
}

pub fn a_server_error_during_the_sweep_waits_and_removes_nothing_test() {
  let cursors = [#(Plans, Cursor(stamp_text(1), Date(2026, 10, 5)))]
  let #(s0, _) = sync.update(sync.new(outbox.new(), cursors, None), started())
  let #(s1, _) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  // CoachGrants come first and have no cursor (a full resync); then the plans page, then the sweep of plans.
  let s2 = answer_all_lists_until_sweep(s1, empty)
  let #(_, commands) = sync.update(s2, Responded(sync.Sweep(Plans), 503, ""))
  assert commands == [RetryIn(2)]
}

fn answer_all_lists_until_sweep(state: Sync, body: String) -> Sync {
  let #(a, _) =
    sync.update(
      state,
      Responded(sync.Pull(collection.CoachGrants, 1), 200, body),
    )
  let #(b, _) = sync.update(a, Responded(sync.Pull(Plans, 1), 200, body))
  b
}

pub fn a_refused_listing_is_skipped_and_the_other_collections_still_sweep_test() {
  let cursors =
    list.map(collection.all, fn(c) {
      #(c, Cursor(stamp_text(1), Date(2026, 10, 5)))
    })
  let #(s0, _) = sync.update(sync.new(outbox.new(), cursors, None), started())
  let #(s1, _) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  let #(s2, _) =
    sync.update(s1, Responded(sync.Pull(collection.CoachGrants, 1), 200, empty))
  // The first sweep is refused with 400: the walk carries on with the next collection's pull.
  let #(_, commands) =
    sync.update(s2, Responded(sync.Sweep(collection.CoachGrants), 400, "{}"))
  assert list.any(commands, fn(c) {
    case c {
      Send(_, sync.Pull(Plans, 1)) -> True
      _ -> False
    }
  })
  assert !list.any(commands, fn(c) {
    case c {
      Reconcile(_, _) -> True
      _ -> False
    }
  })
}

pub fn an_expired_session_during_the_sweep_asks_for_sign_in_test() {
  let cursors = [#(Plans, Cursor(stamp_text(1), Date(2026, 10, 5)))]
  let #(s0, _) = sync.update(sync.new(outbox.new(), cursors, None), started())
  let #(s1, _) = sync.update(s0, Responded(CheckStart, 200, "{}"))
  let empty =
    "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}"
  let s2 = answer_all_lists_until_sweep(s1, empty)
  let #(_, commands) = sync.update(s2, Responded(sync.Sweep(Plans), 401, ""))
  assert commands == [Tell(SignInRequired)]
}
