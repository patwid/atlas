//// Small per-device settings in `localStorage`, such as the session. Values are never empty.
//// Larger data (records, the outbox) belongs in IndexedDB (ADR 0004).

@external(javascript, "./storage.ffi.mjs", "get")
fn do_get(key: String) -> String

@external(javascript, "./storage.ffi.mjs", "set")
pub fn set(key: String, value: String) -> Nil

@external(javascript, "./storage.ffi.mjs", "remove")
pub fn remove(key: String) -> Nil

/// `Error` when the key is missing or storage is unavailable.
pub fn get(key: String) -> Result(String, Nil) {
  case do_get(key) {
    "" -> Error(Nil)
    value -> Ok(value)
  }
}
