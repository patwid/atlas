//// The device clock. Kept apart so the rest of the code takes the time as a plain argument.

@external(javascript, "./clock.ffi.mjs", "nowSeconds")
pub fn now_seconds() -> Int

@external(javascript, "./clock.ffi.mjs", "utcOffsetMinutes")
pub fn utc_offset_minutes() -> Int
