//// The sync engine of ADR 0004, as a pure state machine. A run is: check the session, push the
//// outbox one entry at a time, then pull every collection. The caller executes the `Command`s
//// (HTTP, local storage, notifications) and feeds the answers back as `Event`s, so every protocol
//// decision, including the failure paths, can be tested without a browser or a server.
////
//// Safety rules (ADR 0017): a run starts with a session check, because an invalid token makes
//// PocketBase answer as an anonymous user (empty lists, misleading rejections). Rejections are
//// only final after the session was confirmed valid. A full resync only reconciles (deletes
//// local records the server no longer has) after every page was fetched successfully.

import atlas/api.{type Page, type Request}
import atlas/collection.{type Collection}
import atlas/cursor.{type Cursor, type PullPlan}
import atlas/date.{type Date}
import atlas/outbox.{type Entry, type Outbox}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string

/// Says what an answer is for.
pub type Tag {
  /// The session check at the start of a run.
  CheckStart
  Push(seq: Int)
  /// Confirms the session before a 400/403/404 answer to an entry is treated as a rejection.
  VerifyForPush(seq: Int, reason: String)
  LookupBase(seq: Int)
  Pull(collection: Collection, page: Int)
  /// Confirms the session once the whole pull is done, before cursors and reconciles are committed.
  VerifyForCommit
}

pub type Event {
  /// Begin a run. `token_expired` is what the caller knows from the token's `exp` claim.
  Started(today: Date, token_expired: Bool)
  /// The answer to a `Send`. Status 0 means there was no answer.
  Responded(tag: Tag, status: Int, body: String)
}

pub type Command {
  /// Send the request with the session token and report the answer with this tag.
  Send(request: Request, tag: Tag)
  SaveOutbox(Outbox)
  /// Insert or update these records locally: pulled records (those with unsent local edits are left out)
  /// or the server's answer to a save.
  Apply(collection: Collection, records: List(Dynamic))
  /// After a complete full resync: delete local records of the collection whose IDs are not listed.
  /// Records with unsent local edits must be kept.
  Reconcile(collection: Collection, keep_ids: List(String))
  SaveCursor(collection: Collection, cursor: Cursor)
  Tell(Notice)
  /// Start the run again after this many seconds (or earlier, when the device comes back online).
  RetryIn(seconds: Int)
}

pub type Notice {
  /// The session check answered 200: this is the fresh sign-in response (see `auth.session_from_response`).
  SessionRefreshed(body: String)
  SignInRequired
  /// Entries based on a stale record. For each, pull the server's version and save the edit as a copy.
  Conflicts(entries: List(Entry))
  /// Entries the server will never accept. Tell the user why.
  Rejections(entries: List(Entry), reason: String)
  PullFailed(collection: Collection, status: Int)
  Finished
}

type State {
  Idle
  Starting
  Pushing
  Verifying
  LookingUp
  Pulling(PullState)
  Committing
  Waiting
  SignInNeeded
}

type PullState {
  PullState(
    remaining: List(Collection),
    current: Collection,
    plan: PullPlan,
    updated_seen: List(String),
    ids_seen: List(String),
  )
}

pub opaque type Sync {
  Sync(
    state: State,
    outbox: Outbox,
    cursors: Dict(String, Cursor),
    today: Date,
    failures: Int,
    /// `SaveCursor` and `Reconcile` commands held back until the pull is confirmed.
    commits: List(Command),
    pending_cursors: Dict(String, Cursor),
    /// A start was requested while a run was going on. The run may already have passed what the
    /// requester wanted to see, so another one follows it.
    rerun: Bool,
    /// The newest `updated` this engine has seen for each record (from acknowledged saves and pulls).
    /// Screens read the device database a moment after it changes, so an edit made in that moment would
    /// otherwise be based on an older value and be refused as a conflict.
    known_updated: Dict(String, String),
  )
}

pub fn new(outbox: Outbox, cursors: List(#(Collection, Cursor))) -> Sync {
  Sync(
    state: Idle,
    outbox: outbox,
    cursors: dict.from_list(
      list.map(cursors, fn(pair) { #(collection.to_string(pair.0), pair.1) }),
    ),
    today: date.Date(1970, 1, 1),
    failures: 0,
    commits: [],
    pending_cursors: dict.new(),
    rerun: False,
    known_updated: dict.new(),
  )
}

pub fn outbox(sync: Sync) -> Outbox {
  sync.outbox
}

/// Changes the outbox for a local write. Safe at any time: entries being sent are never altered.
pub fn change_outbox(sync: Sync, change: fn(Outbox) -> Outbox) -> Sync {
  Sync(..sync, outbox: change(sync.outbox))
}

/// The `updated` value to base an edit on: the engine's own newest knowledge of the record, unless the
/// caller's value (read from the device database) is newer. PocketBase timestamps compare as text.
pub fn freshest_base(
  sync: Sync,
  collection: Collection,
  id: String,
  given: String,
) -> String {
  case dict.get(sync.known_updated, record_key(collection, id)) {
    Ok(known) ->
      case string.compare(known, given) {
        order.Gt -> known
        _ -> given
      }
    Error(Nil) -> given
  }
}

fn record_key(collection: Collection, id: String) -> String {
  collection.to_string(collection) <> "/" <> id
}

/// Whether a run is going on. `Started` is ignored while it is.
pub fn is_busy(sync: Sync) -> Bool {
  case sync.state {
    Idle | Waiting | SignInNeeded -> False
    _ -> True
  }
}

pub fn update(sync: Sync, event: Event) -> #(Sync, List(Command)) {
  case event {
    Started(today, token_expired) -> start(sync, today, token_expired)
    Responded(tag, status, body) -> respond(sync, tag, status, body)
  }
}

// START -------------------------------------------------------------------------------------------

fn start(
  sync: Sync,
  today: Date,
  token_expired: Bool,
) -> #(Sync, List(Command)) {
  case is_busy(sync), token_expired {
    True, _ -> #(Sync(..sync, rerun: True), [])
    False, True -> #(Sync(..sync, state: SignInNeeded), [Tell(SignInRequired)])
    False, False -> #(
      Sync(
        ..sync,
        state: Starting,
        today: today,
        outbox: outbox.recover(sync.outbox),
        commits: [],
        pending_cursors: dict.new(),
        rerun: False,
      ),
      [Send(api.refresh(), CheckStart)],
    )
  }
}

// ANSWERS -----------------------------------------------------------------------------------------

fn respond(
  sync: Sync,
  tag: Tag,
  status: Int,
  body: String,
) -> #(Sync, List(Command)) {
  case tag, sync.state {
    CheckStart, Starting ->
      case status {
        200 -> {
          let #(next, commands) = push_next(Sync(..sync, failures: 0))
          #(next, [Tell(SessionRefreshed(body)), ..commands])
        }
        401 -> sign_in_needed(sync)
        _ -> wait(sync)
      }

    Push(seq), Pushing ->
      case find_entry(sync.outbox, seq) {
        Error(Nil) -> #(sync, [])
        Ok(entry) ->
          case api.classify(entry, status, body) {
            api.Final(response) -> {
              let #(next, commands) = apply_response(sync, seq, response)
              let next = remember_saved(next, entry, response)
              #(next, with_saved_record(next, entry, response, body, commands))
            }
            api.CheckSession(reason) -> #(Sync(..sync, state: Verifying), [
              Send(api.refresh(), VerifyForPush(seq, reason)),
            ])
          }
      }

    VerifyForPush(seq, reason), Verifying ->
      case status {
        200 -> apply_response(sync, seq, api.after_session_check(reason, True))
        401 -> apply_response(sync, seq, outbox.Unauthorized)
        _ -> apply_response(sync, seq, outbox.NetworkError)
      }

    LookupBase(seq), LookingUp ->
      case status, api.saved_updated(body) {
        200, Ok(updated) ->
          push_next(
            Sync(..sync, outbox: outbox.with_base(sync.outbox, seq, updated)),
          )
        401, _ -> sign_in_needed(sync)
        400, _ | 403, _ | 404, _ -> #(Sync(..sync, state: Verifying), [
          Send(
            api.refresh(),
            VerifyForPush(seq, "The record is not available on the server."),
          ),
        ])
        _, _ -> wait(sync)
      }

    Pull(collection, _page), Pulling(pull) if collection == pull.current ->
      pulled(sync, pull, status, body)

    VerifyForCommit, Committing ->
      case status {
        200 -> {
          let committed =
            Sync(
              ..sync,
              cursors: dict.merge(sync.cursors, sync.pending_cursors),
              commits: [],
              pending_cursors: dict.new(),
            )
          let #(next, commands) = finish(committed)
          #(next, list.append(sync.commits, commands))
        }
        401 -> sign_in_needed(discard_commits(sync))
        _ -> wait(discard_commits(sync))
      }

    // An answer that no longer belongs to what the engine is doing, for example after a restart.
    _, _ -> #(sync, [])
  }
}

fn remember_saved(sync: Sync, entry: Entry, response: outbox.Response) -> Sync {
  case response {
    outbox.Saved(updated) ->
      Sync(
        ..sync,
        known_updated: dict.insert(
          sync.known_updated,
          record_key(entry.collection, entry.id),
          updated,
        ),
      )
    _ -> sync
  }
}

/// After a save, the server's answer replaces the local copy (new `updated`, server-set fields), unless
/// later edits of the record are still queued: those keep the local copy as it is.
fn with_saved_record(
  sync: Sync,
  entry: Entry,
  response: outbox.Response,
  body: String,
  commands: List(Command),
) -> List(Command) {
  case response, api.saved_record(body) {
    outbox.Saved(_), Ok(record) ->
      case outbox.has_pending(sync.outbox, entry.collection, entry.id) {
        True -> commands
        False -> [Apply(entry.collection, [record]), ..commands]
      }
    _, _ -> commands
  }
}

fn apply_response(
  sync: Sync,
  seq: Int,
  response: outbox.Response,
) -> #(Sync, List(Command)) {
  let #(next_outbox, outcome) =
    outbox.handle_response(sync.outbox, seq, response)
  let sync = Sync(..sync, outbox: next_outbox)
  let save = SaveOutbox(next_outbox)
  case outcome {
    outbox.Continue -> {
      let #(next, commands) = push_next(Sync(..sync, failures: 0))
      #(next, [save, ..commands])
    }
    outbox.RetryAfter(seconds) -> #(
      Sync(..sync, state: Waiting, failures: sync.failures + 1),
      [save, RetryIn(seconds)],
    )
    outbox.NeedsSignIn -> {
      let #(next, commands) = sign_in_needed(sync)
      #(next, [save, ..commands])
    }
    outbox.Conflicted(dropped) -> {
      let #(next, commands) = push_next(sync)
      #(next, [save, Tell(Conflicts(dropped)), ..commands])
    }
    outbox.Failed(dropped, reason) -> {
      let #(next, commands) = push_next(sync)
      #(next, [save, Tell(Rejections(dropped, reason)), ..commands])
    }
  }
}

// PUSH --------------------------------------------------------------------------------------------

fn push_next(sync: Sync) -> #(Sync, List(Command)) {
  case outbox.next(sync.outbox) {
    None -> begin_pull(sync)
    Some(entry) ->
      case outbox.needs_base(entry) {
        True -> #(Sync(..sync, state: LookingUp), [
          Send(
            api.get_record(entry.collection, entry.id),
            LookupBase(entry.seq),
          ),
        ])
        False ->
          case api.entry_request(entry) {
            Ok(request) -> #(
              Sync(
                ..sync,
                state: Pushing,
                outbox: outbox.mark_sending(sync.outbox, entry.seq),
              ),
              [Send(request, Push(entry.seq))],
            )
            // Cannot happen: `needs_base` was checked. Treat it as a rejection rather than looping.
            Error(Nil) ->
              apply_response(
                sync,
                entry.seq,
                outbox.Rejected("The entry could not be sent."),
              )
          }
      }
  }
}

fn find_entry(box: Outbox, seq: Int) -> Result(Entry, Nil) {
  list.find(box.entries, fn(e) { e.seq == seq })
}

// PULL --------------------------------------------------------------------------------------------

fn begin_pull(sync: Sync) -> #(Sync, List(Command)) {
  begin_collection(sync, collection.all)
}

fn begin_collection(
  sync: Sync,
  remaining: List(Collection),
) -> #(Sync, List(Command)) {
  case remaining {
    // Everything was fetched. Before cursors move and records are reconciled, confirm that the
    // session was valid throughout: an invalid token makes the server answer as an anonymous user.
    [] -> #(Sync(..sync, state: Committing), [
      Send(api.refresh(), VerifyForCommit),
    ])
    [current, ..rest] -> {
      let plan = cursor.plan(cursor_of(sync, current), sync.today)
      #(Sync(..sync, state: Pulling(PullState(rest, current, plan, [], []))), [
        Send(api.list_page(current, plan, 1), Pull(current, 1)),
      ])
    }
  }
}

fn pulled(
  sync: Sync,
  pull: PullState,
  status: Int,
  body: String,
) -> #(Sync, List(Command)) {
  case status {
    200 ->
      case api.parse_page(body) {
        Ok(page) -> pulled_page(sync, pull, page)
        Error(Nil) -> wait(sync)
      }
    401 -> sign_in_needed(sync)
    0 -> wait(sync)
    _ if status >= 500 -> wait(sync)
    // The server refuses this collection (for example a rule or filter problem). Report it and carry on.
    _ -> {
      let #(next, commands) = begin_collection(sync, pull.remaining)
      #(next, [Tell(PullFailed(pull.current, status)), ..commands])
    }
  }
}

fn pulled_page(
  sync: Sync,
  pull: PullState,
  page: Page,
) -> #(Sync, List(Command)) {
  let metas = list.filter_map(page.items, api.record_meta)
  let applicable =
    list.filter(page.items, fn(item) {
      case api.record_meta(item) {
        Ok(meta) -> cursor.may_apply(sync.outbox, pull.current, meta.id)
        Error(Nil) -> False
      }
    })
  let sync =
    Sync(
      ..sync,
      known_updated: list.fold(metas, sync.known_updated, fn(known, meta) {
        dict.insert(known, record_key(pull.current, meta.id), meta.updated)
      }),
    )
  let pull =
    PullState(
      ..pull,
      updated_seen: list.append(
        pull.updated_seen,
        list.map(metas, fn(m) { m.updated }),
      ),
      ids_seen: list.append(pull.ids_seen, list.map(metas, fn(m) { m.id })),
    )
  let apply = Apply(pull.current, applicable)
  case api.has_more(page) {
    True -> #(Sync(..sync, state: Pulling(pull)), [
      apply,
      Send(
        api.list_page(pull.current, pull.plan, page.page + 1),
        Pull(pull.current, page.page + 1),
      ),
    ])
    False -> {
      let new_cursor =
        cursor.advance(
          cursor_of(sync, pull.current),
          pull.updated_seen,
          sync.today,
        )
      let reconcile = case pull.plan {
        cursor.FullResync -> [Reconcile(pull.current, pull.ids_seen)]
        cursor.Since(_) -> []
      }
      let held =
        Sync(
          ..sync,
          commits: list.flatten([
            sync.commits,
            reconcile,
            [SaveCursor(pull.current, new_cursor)],
          ]),
          pending_cursors: dict.insert(
            sync.pending_cursors,
            collection.to_string(pull.current),
            new_cursor,
          ),
        )
      let #(next, commands) = begin_collection(held, pull.remaining)
      #(next, [apply, ..commands])
    }
  }
}

/// The end of a run. Local writes made during the pull still have to go out first.
fn finish(sync: Sync) -> #(Sync, List(Command)) {
  case outbox.next(sync.outbox) {
    Some(_) -> push_next(sync)
    None ->
      case sync.rerun {
        // Someone asked for a run while this one was going on: do it now.
        True -> #(
          Sync(
            ..sync,
            state: Starting,
            failures: 0,
            rerun: False,
            commits: [],
            pending_cursors: dict.new(),
          ),
          [Tell(Finished), Send(api.refresh(), CheckStart)],
        )
        False -> #(Sync(..sync, state: Idle, failures: 0), [Tell(Finished)])
      }
  }
}

fn discard_commits(sync: Sync) -> Sync {
  Sync(..sync, commits: [], pending_cursors: dict.new())
}

fn cursor_of(sync: Sync, collection: Collection) -> option.Option(Cursor) {
  case dict.get(sync.cursors, collection.to_string(collection)) {
    Ok(c) -> Some(c)
    Error(Nil) -> None
  }
}

// STOPPING ----------------------------------------------------------------------------------------

fn wait(sync: Sync) -> #(Sync, List(Command)) {
  let failures = sync.failures + 1
  #(Sync(..sync, state: Waiting, failures: failures), [
    RetryIn(outbox.backoff_seconds(failures)),
  ])
}

fn sign_in_needed(sync: Sync) -> #(Sync, List(Command)) {
  #(Sync(..sync, state: SignInNeeded), [Tell(SignInRequired)])
}
