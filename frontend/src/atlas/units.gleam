//// Pace, duration and distance formatting, and heart-rate zones. Pure functions.

import gleam/float
import gleam/int
import gleam/list
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

pub type Zone {
  Zone(number: Int, low: Int, high: Int)
}

/// Five zones as shares of the maximum heart rate: 50-60, 60-70, 70-80, 80-90 and 90-100 percent.
/// The zones do not overlap and zone 5 ends at the maximum. Empty for a non-positive maximum.
pub fn hr_zones(max_hr: Int) -> List(Zone) {
  case max_hr > 0 {
    False -> []
    True -> {
      let lows = [50, 60, 70, 80, 90]
      list.index_map(lows, fn(percent, index) {
        let high = case index {
          4 -> max_hr
          _ -> max_hr * { percent + 10 } / 100 - 1
        }
        Zone(number: index + 1, low: max_hr * percent / 100, high: high)
      })
    }
  }
}

/// The zone number (1-5) for a heart rate. Rates above the maximum count as zone 5.
/// `Error` below zone 1 (under half the maximum) or when the maximum is unusable.
pub fn hr_zone(max_hr: Int, hr: Int) -> Result(Int, Nil) {
  case hr_zones(max_hr) {
    [] -> Error(Nil)
    zones ->
      case hr > max_hr {
        True -> Ok(5)
        False ->
          list.find(zones, fn(zone) { hr >= zone.low && hr <= zone.high })
          |> result_map(fn(zone) { zone.number })
      }
  }
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}

fn result_map(result: Result(a, Nil), f: fn(a) -> b) -> Result(b, Nil) {
  case result {
    Ok(value) -> Ok(f(value))
    Error(Nil) -> Error(Nil)
  }
}
