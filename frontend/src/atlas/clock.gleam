//// The device clock. Kept apart so the rest of the code takes the time as a plain argument.

import atlas/date

@external(javascript, "./clock.ffi.mjs", "nowSeconds")
pub fn now_seconds() -> Int

@external(javascript, "./clock.ffi.mjs", "utcOffsetMinutes")
pub fn utc_offset_minutes() -> Int

/// Today's date on this device.
pub fn today() -> date.Date {
  date.from_unix_seconds(now_seconds(), utc_offset_minutes())
}
