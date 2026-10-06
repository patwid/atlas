//// The mutation outbox of ADR 0004, as a pure state machine. Every local write is recorded here and
//// replayed against PocketBase one entry at a time, in order. The caller does the I/O: it asks for
//// `next`, sends it, and reports the `Response`. Conflicts follow ADR 0011: a stale update is
//// refused with 409 and the client keeps its version as a copy. Deletes are soft (`deleted: true`).
////
//// Field values are stored as already-encoded JSON text (`"\"abc\""`, `"12"`, `"true"`), which
//// keeps merging, comparing and persisting trivial. Build them with the `field_*` helpers.

import atlas/collection.{type Collection}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Fields =
  Dict(String, String)

pub type Kind {
  Create
  Update
}

pub type Entry {
  Entry(
    seq: Int,
    collection: Collection,
    id: String,
    kind: Kind,
    fields: Fields,
    /// The `updated` value the edit is based on. `None` until it is known: the record's earlier
    /// entry has not been acknowledged yet, or a replayed create turned into an update.
    base_updated: Option(String),
    in_flight: Bool,
    attempts: Int,
  )
}

pub type Outbox {
  Outbox(entries: List(Entry), next_seq: Int)
}

/// What the server answered for an entry.
pub type Response {
  /// Saved. `updated` is the record's new `updated` value.
  Saved(updated: String)
  /// 409: the record changed on the server since `base_updated`.
  Conflict
  /// 400 on a create whose ID exists: an earlier attempt took effect.
  AlreadyExists
  /// 400/403/404: the server will never accept this entry.
  Rejected(reason: String)
  /// 401: the session expired. Nothing is lost; sign in again.
  Unauthorized
  /// No answer (offline, timeout, 5xx). Try again later.
  NetworkError
}

/// What the caller has to do after reporting a response.
pub type Outcome {
  /// Carry on with the next entry.
  Continue
  /// Try again after this many seconds.
  RetryAfter(seconds: Int)
  /// Stop and ask the user to sign in again.
  NeedsSignIn
  /// The entry was based on a stale record. All entries for the record were dropped. The caller pulls the
  /// server's version and saves its own edited version as a new record (a "conflicted copy").
  Conflicted(dropped: List(Entry))
  /// The server rejected the entry. All entries for the record were dropped; show the reason.
  Failed(dropped: List(Entry), reason: String)
}

pub fn new() -> Outbox {
  Outbox([], 1)
}

pub fn is_empty(outbox: Outbox) -> Bool {
  outbox.entries == []
}

pub fn pending_count(outbox: Outbox) -> Int {
  list.length(outbox.entries)
}

pub fn has_pending(outbox: Outbox, collection: Collection, id: String) -> Bool {
  list.any(outbox.entries, fn(e) { e.collection == collection && e.id == id })
}

// RECORDING LOCAL WRITES --------------------------------------------------------------------------

pub fn record_create(
  outbox: Outbox,
  collection: Collection,
  id: String,
  fields: Fields,
) -> Outbox {
  append(outbox, collection, id, Create, fields, None)
}

/// Records an edit. `base_updated` is the `updated` value of the local copy being edited.
/// Edits to a record whose entry has not been sent are merged into that entry.
pub fn record_update(
  outbox: Outbox,
  collection: Collection,
  id: String,
  fields: Fields,
  base_updated: String,
) -> Outbox {
  case last_for(outbox, collection, id) {
    Ok(entry) if !entry.in_flight ->
      replace(outbox, Entry(..entry, fields: dict.merge(entry.fields, fields)))
    Ok(_) -> append(outbox, collection, id, Update, fields, None)
    Error(Nil) ->
      append(outbox, collection, id, Update, fields, Some(base_updated))
  }
}

/// Records a soft delete. A record that was created offline and never sent simply disappears from the outbox.
pub fn record_delete(
  outbox: Outbox,
  collection: Collection,
  id: String,
  base_updated: String,
) -> Outbox {
  case last_for(outbox, collection, id) {
    Ok(Entry(kind: Create, in_flight: False, seq: seq, ..)) ->
      Outbox(
        ..outbox,
        entries: list.filter(outbox.entries, fn(e) { e.seq != seq }),
      )
    _ ->
      record_update(
        outbox,
        collection,
        id,
        dict.from_list([field_bool("deleted", True)]),
        base_updated,
      )
  }
}

// REPLAY ------------------------------------------------------------------------------------------

/// The entry to send now: the oldest one, unless it is already being sent. Strictly one at a time,
/// so a record's create always reaches the server before its edits and children.
pub fn next(outbox: Outbox) -> Option(Entry) {
  case outbox.entries {
    [first, ..] if !first.in_flight -> Some(first)
    _ -> None
  }
}

pub fn mark_sending(outbox: Outbox, seq: Int) -> Outbox {
  update_entry(outbox, seq, fn(e) { Entry(..e, in_flight: True) })
}

/// After a restart nothing is in flight any more. Resending is safe: a create that took effect
/// answers `AlreadyExists`, and an update that took effect is accepted again by the server (ADR 0011).
pub fn recover(outbox: Outbox) -> Outbox {
  Outbox(
    ..outbox,
    entries: list.map(outbox.entries, fn(e) { Entry(..e, in_flight: False) }),
  )
}

/// An update without a known base has to look the record's `updated` up before it is sent.
pub fn needs_base(entry: Entry) -> Bool {
  entry.kind == Update && entry.base_updated == None
}

pub fn with_base(outbox: Outbox, seq: Int, updated: String) -> Outbox {
  update_entry(outbox, seq, fn(e) { Entry(..e, base_updated: Some(updated)) })
}

pub fn handle_response(
  outbox: Outbox,
  seq: Int,
  response: Response,
) -> #(Outbox, Outcome) {
  case find(outbox, seq) {
    Error(Nil) -> #(outbox, Continue)
    Ok(entry) ->
      case response {
        Saved(updated) -> #(saved(outbox, entry, updated), Continue)
        NetworkError -> {
          let attempts = entry.attempts + 1
          #(
            update_entry(outbox, seq, fn(e) {
              Entry(..e, in_flight: False, attempts: attempts)
            }),
            RetryAfter(backoff_seconds(attempts)),
          )
        }
        Unauthorized -> #(
          update_entry(outbox, seq, fn(e) { Entry(..e, in_flight: False) }),
          NeedsSignIn,
        )
        AlreadyExists ->
          case entry.kind {
            Create -> #(
              update_entry(outbox, seq, fn(e) {
                Entry(..e, kind: Update, base_updated: None, in_flight: False)
              }),
              Continue,
            )
            Update ->
              rejected(
                outbox,
                entry,
                "The server says this record already exists.",
              )
          }
        Rejected(reason) -> rejected(outbox, entry, reason)
        Conflict ->
          case entry.kind {
            Update -> {
              let #(rest, dropped) =
                drop_record(outbox, entry.collection, entry.id)
              #(rest, Conflicted(dropped))
            }
            Create -> rejected(outbox, entry, "A create cannot conflict.")
          }
      }
  }
}

/// Seconds to wait after the nth failed attempt: 2, 4, 8, ... up to 5 minutes.
pub fn backoff_seconds(attempts: Int) -> Int {
  let exponent = int.min(int.max(attempts, 1), 8)
  int.min(pow2(exponent), 300)
}

/// The JSON request body for an entry: its fields, plus `id` for a create or `base_updated` for an update.
pub fn request_body(entry: Entry) -> String {
  let extra = case entry.kind, entry.base_updated {
    Create, _ -> [#("id", encode_string(entry.id))]
    Update, Some(base) -> [#("base_updated", encode_string(base))]
    Update, None -> []
  }
  let pairs =
    list.append(dict.to_list(entry.fields), extra)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  "{"
  <> string.join(
    list.map(pairs, fn(pair) { encode_string(pair.0) <> ":" <> pair.1 }),
    ",",
  )
  <> "}"
}

// FIELD VALUES ------------------------------------------------------------------------------------

pub fn field_string(name: String, value: String) -> #(String, String) {
  #(name, encode_string(value))
}

pub fn field_bool(name: String, value: Bool) -> #(String, String) {
  #(name, json.to_string(json.bool(value)))
}

pub fn field_int(name: String, value: Int) -> #(String, String) {
  #(name, json.to_string(json.int(value)))
}

pub fn field_float(name: String, value: Float) -> #(String, String) {
  #(name, json.to_string(json.float(value)))
}

pub fn field_null(name: String) -> #(String, String) {
  #(name, "null")
}

// PERSISTENCE -------------------------------------------------------------------------------------

pub fn to_json_string(outbox: Outbox) -> String {
  json.object([
    #("next_seq", json.int(outbox.next_seq)),
    #("entries", json.array(outbox.entries, entry_to_json)),
  ])
  |> json.to_string
}

pub fn from_json_string(text: String) -> Result(Outbox, Nil) {
  case json.parse(text, outbox_decoder()) {
    Ok(outbox) -> Ok(outbox)
    Error(_) -> Error(Nil)
  }
}

fn entry_to_json(e: Entry) -> json.Json {
  json.object([
    #("seq", json.int(e.seq)),
    #("collection", json.string(collection.to_string(e.collection))),
    #("id", json.string(e.id)),
    #(
      "kind",
      json.string(case e.kind {
        Create -> "create"
        Update -> "update"
      }),
    ),
    #("fields", json.dict(e.fields, fn(key) { key }, json.string)),
    #("base_updated", json.nullable(e.base_updated, json.string)),
    #("in_flight", json.bool(e.in_flight)),
    #("attempts", json.int(e.attempts)),
  ])
}

fn outbox_decoder() -> decode.Decoder(Outbox) {
  use next_seq <- decode.field("next_seq", decode.int)
  use entries <- decode.field("entries", decode.list(entry_decoder()))
  decode.success(Outbox(entries, next_seq))
}

fn entry_decoder() -> decode.Decoder(Entry) {
  use seq <- decode.field("seq", decode.int)
  use collection <- decode.field("collection", collection_decoder())
  use id <- decode.field("id", decode.string)
  use kind <- decode.field("kind", kind_decoder())
  use fields <- decode.field(
    "fields",
    decode.dict(decode.string, decode.string),
  )
  use base_updated <- decode.field(
    "base_updated",
    decode.optional(decode.string),
  )
  use in_flight <- decode.field("in_flight", decode.bool)
  use attempts <- decode.field("attempts", decode.int)
  decode.success(Entry(
    seq,
    collection,
    id,
    kind,
    fields,
    base_updated,
    in_flight,
    attempts,
  ))
}

fn collection_decoder() -> decode.Decoder(Collection) {
  use text <- decode.then(decode.string)
  case collection.from_string(text) {
    Ok(c) -> decode.success(c)
    Error(Nil) -> decode.failure(collection.Plans, "Collection")
  }
}

fn kind_decoder() -> decode.Decoder(Kind) {
  use text <- decode.then(decode.string)
  case text {
    "create" -> decode.success(Create)
    "update" -> decode.success(Update)
    _ -> decode.failure(Create, "Kind")
  }
}

// INTERNALS ---------------------------------------------------------------------------------------

fn append(
  outbox: Outbox,
  collection: Collection,
  id: String,
  kind: Kind,
  fields: Fields,
  base_updated: Option(String),
) -> Outbox {
  let entry =
    Entry(outbox.next_seq, collection, id, kind, fields, base_updated, False, 0)
  Outbox(
    entries: list.append(outbox.entries, [entry]),
    next_seq: outbox.next_seq + 1,
  )
}

fn find(outbox: Outbox, seq: Int) -> Result(Entry, Nil) {
  list.find(outbox.entries, fn(e) { e.seq == seq })
}

fn last_for(
  outbox: Outbox,
  collection: Collection,
  id: String,
) -> Result(Entry, Nil) {
  list.filter(outbox.entries, fn(e) { e.collection == collection && e.id == id })
  |> list.last
}

fn replace(outbox: Outbox, entry: Entry) -> Outbox {
  update_entry(outbox, entry.seq, fn(_) { entry })
}

fn update_entry(outbox: Outbox, seq: Int, f: fn(Entry) -> Entry) -> Outbox {
  Outbox(
    ..outbox,
    entries: list.map(outbox.entries, fn(e) {
      case e.seq == seq {
        True -> f(e)
        False -> e
      }
    }),
  )
}

fn drop_record(
  outbox: Outbox,
  collection: Collection,
  id: String,
) -> #(Outbox, List(Entry)) {
  let #(dropped, kept) =
    list.partition(outbox.entries, fn(e) {
      e.collection == collection && e.id == id
    })
  #(Outbox(..outbox, entries: kept), dropped)
}

fn rejected(
  outbox: Outbox,
  entry: Entry,
  reason: String,
) -> #(Outbox, Outcome) {
  let #(rest, dropped) = drop_record(outbox, entry.collection, entry.id)
  #(rest, Failed(dropped, reason))
}

/// Removes the acknowledged entry and hands its new `updated` to the record's later entries.
fn saved(outbox: Outbox, entry: Entry, updated: String) -> Outbox {
  Outbox(
    ..outbox,
    entries: outbox.entries
      |> list.filter(fn(e) { e.seq != entry.seq })
      |> list.map(fn(e) {
        case
          e.collection == entry.collection
          && e.id == entry.id
          && e.base_updated == None
        {
          True -> Entry(..e, base_updated: Some(updated))
          False -> e
        }
      }),
  )
}

fn encode_string(text: String) -> String {
  json.to_string(json.string(text))
}

fn pow2(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> 2 * pow2(n - 1)
  }
}
