//// Runs the sync engine (ADR 0018) in the app: loads the device database, executes the engine's
//// commands as effects, and offers the local writes that pages use (ADR 0019, 0020).
////
//// This module has its own state and message type, which the app embeds. Things the app has to act
//// on (a fresh session, "sign in again", conflicts) come back as notices.

import atlas/api
import atlas/auth
import atlas/collection.{type Collection}
import atlas/conflict
import atlas/cursor
import atlas/date
import atlas/http
import atlas/local
import atlas/outbox
import atlas/random
import atlas/store
import atlas/sync.{type Command, type Notice, type Sync}
import atlas/timer
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}

pub type Phase {
  /// No user yet, or signed out.
  NotLoaded
  Loading
  Ready
  /// The device database could not be opened or read. Nothing is synced and nothing is overwritten.
  Unavailable
}

pub type State {
  State(
    sync: Option(Sync),
    phase: Phase,
    /// A write to the device database failed (for example because storage is full).
    write_failed: Bool,
    /// Things the user should know: conflicts and rejections, newest first.
    problems: List(String),
  )
}

/// What a call needs to know about the session and the clock. The caller supplies it, so this module
/// does not read the time itself.
pub type Context {
  Context(token: String, now_seconds: Int, utc_offset_minutes: Int)
}

pub type Msg {
  Loaded(Result(local.Loaded, Nil))
  Responded(sync.Tag, http.Response)
  /// Start a run now (a no-op while one is going on or before loading).
  Kick
  Wrote(Bool)
  /// The local version of a record whose edit clashed with a newer server version.
  LocalVersion(Collection, String, Result(Option(Dynamic), Nil))
  /// The server's current version of a record, fetched after a conflict or rejection.
  ServerVersion(Collection, String, http.Response)
}

pub fn new() -> State {
  State(None, NotLoaded, False, [])
}

pub fn is_ready(state: State) -> Bool {
  state.phase == Ready
}

/// Opens the device database for this user and restores the outbox and cursors.
pub fn load(state: State, user_id: String) -> #(State, Effect(Msg)) {
  #(
    State(..state, phase: Loading),
    effect.from(fn(dispatch) {
      local.load(user_id, fn(result) { dispatch(Loaded(result)) })
    }),
  )
}

/// Back to the start, for sign-out. The device database keeps its data (ADR 0019).
pub fn reset(state: State) -> State {
  State(..state, sync: None, phase: NotLoaded)
}

pub fn update(
  state: State,
  msg: Msg,
  context: Context,
) -> #(State, Effect(Msg), List(Notice)) {
  case msg {
    Loaded(Ok(loaded)) -> {
      let ready =
        State(
          ..state,
          sync: Some(sync.new(loaded.outbox, loaded.cursors)),
          phase: Ready,
        )
      let persist =
        effect.from(fn(_) { store.request_persistence(fn(_) { Nil }) })
      let #(next, effect, notices) = kick(ready, context)
      #(next, effect.batch([persist, effect]), notices)
    }
    Loaded(Error(Nil)) -> #(
      State(..state, phase: Unavailable),
      effect.none(),
      [],
    )

    Kick -> kick(state, context)

    Responded(tag, response) ->
      run(state, sync.Responded(tag, response.status, response.body), context)

    Wrote(True) -> #(state, effect.none(), [])
    Wrote(False) -> #(State(..state, write_failed: True), effect.none(), [])

    LocalVersion(collection, id, Ok(Some(record))) ->
      keep_local_version(state, collection, id, record, context)
    LocalVersion(collection, id, _) -> #(
      state,
      fetch_server_version(collection, id, context),
      [],
    )

    ServerVersion(collection, id, response) -> #(
      state,
      store_server_version(state, collection, id, response),
      [],
    )
  }
}

/// Forget the listed problems after the user has seen them.
pub fn dismiss_problems(state: State) -> State {
  State(..state, problems: [])
}

fn kick(state: State, context: Context) -> #(State, Effect(Msg), List(Notice)) {
  let today =
    date.from_unix_seconds(context.now_seconds, context.utc_offset_minutes)
  run(
    state,
    sync.Started(today, auth.is_expired(context.token, context.now_seconds)),
    context,
  )
}

fn run(
  state: State,
  event: sync.Event,
  context: Context,
) -> #(State, Effect(Msg), List(Notice)) {
  case state.sync {
    None -> #(state, effect.none(), [])
    Some(engine) -> {
      let #(next, commands) = sync.update(engine, event)
      let effects = list.map(commands, execute(_, next, context))
      let notices =
        list.filter_map(commands, fn(command) {
          case command {
            sync.Tell(notice) -> Ok(notice)
            _ -> Error(Nil)
          }
        })
      let state = State(..state, sync: Some(next))
      let #(state, follow_ups, for_the_app) =
        handle_notices(state, notices, context)
      #(state, effect.batch(list.append(effects, follow_ups)), for_the_app)
    }
  }
}

/// Conflicts, rejections and pull failures are dealt with here. What is left (a fresh session,
/// "sign in again") is for the app.
fn handle_notices(
  state: State,
  notices: List(Notice),
  context: Context,
) -> #(State, List(Effect(Msg)), List(Notice)) {
  list.fold(notices, #(state, [], []), fn(acc, notice) {
    let #(current, effects, for_the_app) = acc
    case notice {
      sync.Conflicts(entries) -> {
        let records = distinct_records(entries)
        let more =
          list.map(records, fn(record) {
            let #(collection, id) = record
            case conflict.copyable(collection) {
              True -> read_local_version(collection, id)
              False -> fetch_server_version(collection, id, context)
            }
          })
        let uncopied =
          list.filter(records, fn(record) { !conflict.copyable(record.0) })
          |> list.map(fn(record) {
            "A change to a "
            <> collection.label(record.0)
            <> " clashed with a newer one made elsewhere; the newer version was kept."
          })
        #(
          add_problems(current, uncopied),
          list.append(effects, more),
          for_the_app,
        )
      }
      sync.Rejections(entries, reason) -> {
        let more =
          list.map(distinct_records(entries), fn(record) {
            let #(collection, id) = record
            let created_here =
              list.any(entries, fn(entry) {
                entry.collection == collection
                && entry.id == id
                && entry.kind == outbox.Create
              })
            case created_here {
              True ->
                effect.from(fn(dispatch) {
                  store.delete_record(collection, id, fn(ok) {
                    dispatch(Wrote(ok))
                  })
                })
              False -> fetch_server_version(collection, id, context)
            }
          })
        #(
          add_problems(current, [
            "The server did not accept a change: " <> reason,
          ]),
          list.append(effects, more),
          for_the_app,
        )
      }
      sync.PullFailed(collection, status) -> #(
        add_problems(current, [
          "Could not load "
          <> collection.label(collection)
          <> "s (HTTP "
          <> int.to_string(status)
          <> ").",
        ]),
        effects,
        for_the_app,
      )
      other -> #(current, effects, list.append(for_the_app, [other]))
    }
  })
}

fn distinct_records(
  entries: List(outbox.Entry),
) -> List(#(Collection, String)) {
  entries
  |> list.map(fn(entry) { #(entry.collection, entry.id) })
  |> list.unique
}

fn add_problems(state: State, messages: List(String)) -> State {
  State(
    ..state,
    problems: list.take(list.append(list.reverse(messages), state.problems), 20),
  )
}

fn read_local_version(collection: Collection, id: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_record(collection, id, fn(result) {
      dispatch(LocalVersion(collection, id, result))
    })
  })
}

fn fetch_server_version(
  collection: Collection,
  id: String,
  context: Context,
) -> Effect(Msg) {
  http.send(api.get_record(collection, id), Some(context.token), fn(response) {
    ServerVersion(collection, id, response)
  })
}

/// The user's version of a record that changed elsewhere: save it as a new record (the conflicted
/// copy) where that makes sense, then bring in the server's version of the original.
fn keep_local_version(
  state: State,
  collection: Collection,
  id: String,
  record: Dynamic,
  context: Context,
) -> #(State, Effect(Msg), List(Notice)) {
  let stored = store.record_fields(record)
  let fetch = fetch_server_version(collection, id, context)
  case state.sync, conflict.copy_fields(collection, stored) {
    Some(engine), Some(fields) -> {
      let copy_id = random.new_id()
      let changed =
        sync.change_outbox(engine, fn(box) {
          outbox.record_create(box, collection, copy_id, fields)
        })
      let name = conflict.title_of(stored)
      let message =
        "A change to \""
        <> name
        <> "\" clashed with a newer one made elsewhere. Your version was kept as \""
        <> name
        <> conflict.copy_suffix
        <> "\"."
      #(
        add_problems(State(..state, sync: Some(changed)), [message]),
        effect.batch([
          effect.from(fn(dispatch) {
            store.merge_json(
              collection,
              copy_id,
              outbox.fields_json(fields),
              fn(ok) { dispatch(Wrote(ok)) },
            )
          }),
          write_meta(
            local.outbox_key,
            outbox.to_json_string(sync.outbox(changed)),
          ),
          fetch,
          effect.from(fn(dispatch) { dispatch(Kick) }),
        ]),
        [],
      )
    }
    _, _ -> #(
      add_problems(state, [
        "A change to a "
        <> collection.label(collection)
        <> " clashed with a newer one made elsewhere; the newer version was kept.",
      ]),
      fetch,
      [],
    )
  }
}

/// Puts the server's version of a record in the device database. Skipped while the user has
/// newer unsent changes for it: they would be overwritten.
fn store_server_version(
  state: State,
  collection: Collection,
  id: String,
  response: http.Response,
) -> Effect(Msg) {
  let pending = case state.sync {
    Some(engine) -> outbox.has_pending(sync.outbox(engine), collection, id)
    None -> True
  }
  case pending, response.status, api.saved_record(response.body) {
    True, _, _ -> effect.none()
    False, 200, Ok(record) ->
      effect.from(fn(dispatch) {
        store.put_records(collection, [record], fn(ok) { dispatch(Wrote(ok)) })
      })
    // The server no longer shows it to this user: it is gone for them too.
    False, 404, _ ->
      effect.from(fn(dispatch) {
        store.delete_record(collection, id, fn(ok) { dispatch(Wrote(ok)) })
      })
    _, _, _ -> effect.none()
  }
}

/// Turns one engine command into an effect. `engine` is the engine after the step that produced it.
fn execute(command: Command, engine: Sync, context: Context) -> Effect(Msg) {
  case command {
    sync.Send(request, tag) ->
      http.send(request, Some(context.token), fn(response) {
        Responded(tag, response)
      })
    sync.SaveOutbox(box) ->
      write_meta(local.outbox_key, outbox.to_json_string(box))
    sync.SaveCursor(collection, saved) ->
      write_meta(local.cursor_key(collection), cursor.to_json_string(saved))
    sync.Apply(collection, records) ->
      effect.from(fn(dispatch) {
        store.put_records(collection, records, fn(ok) { dispatch(Wrote(ok)) })
      })
    sync.Reconcile(collection, keep_ids) ->
      effect.from(fn(dispatch) {
        store.delete_missing(
          collection,
          keep_ids,
          pending_ids(sync.outbox(engine), collection),
          fn(ok) { dispatch(Wrote(ok)) },
        )
      })
    sync.RetryIn(seconds) -> timer.after(seconds, Kick)
    // Notices are returned to the app, not executed.
    sync.Tell(_) -> effect.none()
  }
}

fn write_meta(key: String, value: String) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.put_meta(key, value, fn(ok) { dispatch(Wrote(ok)) })
  })
}

/// IDs of records of the collection that still have unsent changes.
fn pending_ids(box: outbox.Outbox, collection: Collection) -> List(String) {
  box.entries
  |> list.filter(fn(entry) { entry.collection == collection })
  |> list.map(fn(entry) { entry.id })
}

// LOCAL WRITES ------------------------------------------------------------------------------------

/// A new record made on this device. It is stored locally at once and queued for upload.
/// `fields` are the record's values as encoded JSON text (see `outbox.field_string` and friends).
pub fn create(
  state: State,
  collection: Collection,
  id: String,
  fields: outbox.Fields,
) -> #(State, Effect(Msg)) {
  write(state, collection, id, fields, fn(box) {
    outbox.record_create(box, collection, id, fields)
  })
}

/// An edit of a record. `base_updated` is the `updated` value of the local copy being edited.
pub fn edit(
  state: State,
  collection: Collection,
  id: String,
  fields: outbox.Fields,
  base_updated: String,
) -> #(State, Effect(Msg)) {
  write(state, collection, id, fields, fn(box) {
    outbox.record_update(box, collection, id, fields, base_updated)
  })
}

/// A soft delete (ADR 0009).
pub fn delete(
  state: State,
  collection: Collection,
  id: String,
  base_updated: String,
) -> #(State, Effect(Msg)) {
  let fields = dict.from_list([outbox.field_bool("deleted", True)])
  write(state, collection, id, fields, fn(box) {
    outbox.record_delete(box, collection, id, base_updated)
  })
}

fn write(
  state: State,
  collection: Collection,
  id: String,
  fields: outbox.Fields,
  change: fn(outbox.Outbox) -> outbox.Outbox,
) -> #(State, Effect(Msg)) {
  case state.sync {
    // Not loaded: nothing may be written, or it would be lost.
    None -> #(state, effect.none())
    Some(engine) -> {
      let changed = sync.change_outbox(engine, change)
      #(
        State(..state, sync: Some(changed)),
        effect.batch([
          // The record first, then the outbox entry that describes it (ADR 0019).
          effect.from(fn(dispatch) {
            store.merge_json(collection, id, outbox.fields_json(fields), fn(ok) {
              dispatch(Wrote(ok))
            })
          }),
          write_meta(
            local.outbox_key,
            outbox.to_json_string(sync.outbox(changed)),
          ),
          effect.from(fn(dispatch) { dispatch(Kick) }),
        ]),
      )
    }
  }
}
