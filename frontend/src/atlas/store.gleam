//// The device database in IndexedDB (ADR 0019): synced records per collection, and small `meta`
//// values (the outbox, cursors, the owner). Callback style, so several steps can be chained
//// inside one effect. Every callback gets a plain result: `False` or `Error` mean IndexedDB failed.

import atlas/collection.{type Collection}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/option.{type Option}

@external(javascript, "./store.ffi.mjs", "open")
fn do_open(name: String, callback: fn(Bool) -> Nil) -> Nil

@external(javascript, "./store.ffi.mjs", "putRecords")
fn do_put_records(
  collection: String,
  records: List(Dynamic),
  callback: fn(Bool, Dynamic) -> Nil,
) -> Nil

@external(javascript, "./store.ffi.mjs", "mergeJson")
fn do_merge_json(
  collection: String,
  id: String,
  patch: String,
  callback: fn(Bool, Dynamic) -> Nil,
) -> Nil

@external(javascript, "./store.ffi.mjs", "getRecord")
fn do_get_record(
  collection: String,
  id: String,
  callback: fn(Bool, Dynamic) -> Nil,
) -> Nil

@external(javascript, "./store.ffi.mjs", "getAll")
fn do_get_all(
  collection: String,
  callback: fn(Bool, List(Dynamic)) -> Nil,
) -> Nil

@external(javascript, "./store.ffi.mjs", "deleteRecord")
fn do_delete_record(
  collection: String,
  id: String,
  callback: fn(Bool, Dynamic) -> Nil,
) -> Nil

@external(javascript, "./store.ffi.mjs", "deleteMissing")
fn do_delete_missing(
  collection: String,
  keep: List(String),
  protected: List(String),
  callback: fn(Bool, Dynamic) -> Nil,
) -> Nil

@external(javascript, "./store.ffi.mjs", "getMeta")
fn do_get_meta(key: String, callback: fn(Bool, String) -> Nil) -> Nil

@external(javascript, "./store.ffi.mjs", "putMeta")
fn do_put_meta(
  key: String,
  value: String,
  callback: fn(Bool, Dynamic) -> Nil,
) -> Nil

@external(javascript, "./store.ffi.mjs", "clearAll")
fn do_clear_all(callback: fn(Bool, Dynamic) -> Nil) -> Nil

@external(javascript, "./store.ffi.mjs", "requestPersistence")
fn do_request_persistence(callback: fn(Bool) -> Nil) -> Nil

pub fn open(name: String, callback: fn(Bool) -> Nil) -> Nil {
  do_open(name, callback)
}

pub fn put_records(
  collection: Collection,
  records: List(Dynamic),
  callback: fn(Bool) -> Nil,
) -> Nil {
  do_put_records(collection.to_string(collection), records, fn(ok, _) {
    callback(ok)
  })
}

/// Merges `patch` (JSON text of an object) into the stored record, or creates the record from it.
pub fn merge_json(
  collection: Collection,
  id: String,
  patch: String,
  callback: fn(Bool) -> Nil,
) -> Nil {
  do_merge_json(collection.to_string(collection), id, patch, fn(ok, _) {
    callback(ok)
  })
}

/// `Ok(None)` when there is no such record.
pub fn get_record(
  collection: Collection,
  id: String,
  callback: fn(Result(Option(Dynamic), Nil)) -> Nil,
) -> Nil {
  do_get_record(collection.to_string(collection), id, fn(ok, value) {
    case ok, decode.run(value, decode.optional(decode.dynamic)) {
      True, Ok(found) -> callback(Ok(found))
      _, _ -> callback(Error(Nil))
    }
  })
}

pub fn get_all(
  collection: Collection,
  callback: fn(Result(List(Dynamic), Nil)) -> Nil,
) -> Nil {
  do_get_all(collection.to_string(collection), fn(ok, records) {
    case ok {
      True -> callback(Ok(records))
      False -> callback(Error(Nil))
    }
  })
}

pub fn delete_record(
  collection: Collection,
  id: String,
  callback: fn(Bool) -> Nil,
) -> Nil {
  do_delete_record(collection.to_string(collection), id, fn(ok, _) {
    callback(ok)
  })
}

/// Deletes the collection's records whose ID is in neither list.
pub fn delete_missing(
  collection: Collection,
  keep: List(String),
  protected: List(String),
  callback: fn(Bool) -> Nil,
) -> Nil {
  do_delete_missing(
    collection.to_string(collection),
    keep,
    protected,
    fn(ok, _) { callback(ok) },
  )
}

/// `Ok("")` when the key has never been written.
pub fn get_meta(key: String, callback: fn(Result(String, Nil)) -> Nil) -> Nil {
  do_get_meta(key, fn(ok, value) {
    case ok {
      True -> callback(Ok(value))
      False -> callback(Error(Nil))
    }
  })
}

pub fn put_meta(key: String, value: String, callback: fn(Bool) -> Nil) -> Nil {
  do_put_meta(key, value, fn(ok, _) { callback(ok) })
}

/// Removes every record and meta value.
pub fn clear(callback: fn(Bool) -> Nil) -> Nil {
  do_clear_all(fn(ok, _) { callback(ok) })
}

/// Asks the browser not to evict the database under storage pressure (ADR 0004).
pub fn request_persistence(callback: fn(Bool) -> Nil) -> Nil {
  do_request_persistence(callback)
}
