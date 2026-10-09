//// Pace, duration and distance formatting. Pure functions. Heart-rate zones are in `hr_zones`.

import gleam/float
import gleam/int
import gleam/string

/// Seconds per kilometre, rounded. `Error` when there is no distance or no time to divide.
pub fn pace_seconds_per_km(
  distance_m: Float,
  seconds: Int,
) -> Result(Int, Nil) {
  case distance_m >. 0.0 && seconds > 0 {
    True -> Ok(float.round(int.to_float(seconds) *. 1000.0 /. distance_m))
    False -> Error(Nil)
  }
}

/// `5:30 /km`
pub fn format_pace(seconds_per_km: Int) -> String {
  format_duration(seconds_per_km) <> " /km"
}

/// `45:10` below an hour and `1:02:03` from an hour on. Negative values count as zero.
pub fn format_duration(seconds: Int) -> String {
  let s = int.max(seconds, 0)
  let hours = s / 3600
  let minutes = { s % 3600 } / 60
  let secs = s % 60
  case hours > 0 {
    True -> int.to_string(hours) <> ":" <> pad2(minutes) <> ":" <> pad2(secs)
    False -> int.to_string(minutes) <> ":" <> pad2(secs)
  }
}

/// `10.23 km`, rounded to two decimals. Negative values count as zero.
pub fn format_distance_km(distance_m: Float) -> String {
  let hundredths = float.round(float.max(distance_m, 0.0) /. 10.0)
  int.to_string(hundredths / 100) <> "." <> pad2(hundredths % 100) <> " km"
}

/// A planned distance, such as a workout's or a week's: `16 km`, `8.5 km`. Plans are written in round numbers, so
/// at most one decimal and none for a whole kilometre (ADR 0071); what was run keeps `format_distance_km`.
pub fn format_planned_km(distance_m: Float) -> String {
  planned_km(distance_m) <> " km"
}

/// `format_planned_km` without the unit, for a pair such as `16 / 32 km`.
pub fn planned_km(distance_m: Float) -> String {
  let tenths = float.round(float.max(distance_m, 0.0) /. 100.0)
  case tenths % 10 {
    0 -> int.to_string(tenths / 10)
    rest -> int.to_string(tenths / 10) <> "." <> int.to_string(rest)
  }
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}
