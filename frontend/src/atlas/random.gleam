//// Randomness for new record IDs.

import atlas/id

@external(javascript, "./random.ffi.mjs", "randomInt")
pub fn random_int(n: Int) -> Int

/// A fresh record ID (ADR 0004).
pub fn new_id() -> String {
  id.generate(random_int)
}
