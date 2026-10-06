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

@external(javascript, "./clock.ffi.mjs", "utcOffsetAtLocal")
fn do_offset_at_local(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
) -> Int

@external(javascript, "./clock.ffi.mjs", "utcOffsetAtUtc")
pub fn utc_offset_at_utc(timestamp: String) -> Int

/// The UTC offset in minutes that applies at a local date and time on this device.
pub fn utc_offset_at_local(day: date.Date, hour: Int, minute: Int) -> Int {
  do_offset_at_local(day.year, day.month, day.day, hour, minute)
}
