//// Pace zones as an explicit setting (ADR 0036): a threshold pace and where each of the five zones starts, in
//// seconds per kilometre. Zone 1 is the slowest; each zone starts at the slowest pace that still counts for it,
//// and zone 5 is open towards faster. Until the athlete saves their own, the defaults are used: zones from 140,
//// 129, 114, 106 and 99 percent of the time per km of a 5:00 /km threshold. Pure.

import atlas/units
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const default_threshold_s = 300

/// The fastest and slowest pace a value may have (the server's limits): 2:00 to 15:00 /km.
pub const fastest_s = 120

pub const slowest_s = 900

pub type PaceZones {
  /// `starts` has five entries in seconds per km, each faster (smaller) than the one before.
  PaceZones(threshold_s: Int, starts: List(Int))
}

pub type Zone {
  /// `slowest` is where the zone starts; `fastest` is `None` for zone 5, which has no faster end.
  Zone(number: Int, slowest: Int, fastest: Option(Int))
}

/// What the form holds: the text of the threshold pace and of the five starts (`5:00`).
pub type Form {
  Form(threshold: String, starts: List(String))
}

/// The default zones for a threshold pace: starts at 140, 129, 114, 106 and 99 percent of its time per km,
/// rounded down to whole seconds.
pub fn defaults(threshold_s: Int) -> PaceZones {
  PaceZones(
    threshold_s,
    list.map([140, 129, 114, 106, 99], fn(percent) {
      threshold_s * percent / 100
    }),
  )
}

/// The zones with both ends. A zone ends one second per km slower than the next one's start; zone 5 is open.
pub fn zones(settings: PaceZones) -> List(Zone) {
  let ends =
    list.append(
      list.map(list.drop(settings.starts, 1), fn(start) { Some(start + 1) }),
      [None],
    )
  list.zip(settings.starts, ends)
  |> list.index_map(fn(pair, index) { Zone(index + 1, pair.0, pair.1) })
}

/// The zone number (1-5) for a pace in seconds per km. `Error` when slower than the start of zone 1.
pub fn zone_of(settings: PaceZones, pace_s: Int) -> Result(Int, Nil) {
  zones(settings)
  |> list.find(fn(zone) {
    pace_s <= zone.slowest
    && case zone.fastest {
      Some(fastest) -> pace_s >= fastest
      None -> True
    }
  })
  |> result.map(fn(zone) { zone.number })
}

/// `5:00`
pub fn format(pace_s: Int) -> String {
  units.format_duration(pace_s)
}

pub fn to_form(settings: PaceZones) -> Form {
  Form(format(settings.threshold_s), list.map(settings.starts, format))
}

/// The form with the zones worked out again from the threshold pace it holds (the default percentages).
/// `Error` when the threshold pace is not usable.
pub fn fill_from_threshold(form: Form) -> Result(Form, String) {
  pace(form.threshold, "threshold pace")
  |> result.map(fn(threshold) { to_form(defaults(threshold)) })
}

/// Checks the form: paces as `m:ss` (or whole minutes) from 2:00 to 15:00 /km, each zone faster than the one
/// before.
pub fn parse(form: Form) -> Result(PaceZones, String) {
  parse_at(form) |> result.map_error(fn(problem) { problem.1 })
}

/// `parse`, with the input each problem is about (ADR 0077): 0 for the threshold, 1 to 5 for a zone's start, -1
/// for the whole form.
pub fn parse_at(form: Form) -> Result(PaceZones, #(Int, String)) {
  use threshold <- result.try(
    pace(form.threshold, "threshold pace")
    |> result.map_error(fn(message) { #(0, message) }),
  )
  use starts <- result.try(
    list.index_map(form.starts, fn(text, index) {
      pace(text, "start of pace zone " <> int.to_string(index + 1))
      |> result.map_error(fn(message) { #(index + 1, message) })
    })
    |> result.all,
  )
  case list.length(starts) == 5 {
    False -> Error(#(-1, "There must be five pace zones."))
    True -> {
      use _ <- result.try(faster(starts, 1))
      Ok(PaceZones(threshold, starts))
    }
  }
}

/// The stored field for the threshold pace, in seconds per km.
pub const threshold_field = "threshold_pace_s"

/// The stored field for where zone `number` starts: `pace_zone1_start_s` to `pace_zone5_start_s`.
pub fn start_field(number: Int) -> String {
  "pace_zone" <> int.to_string(number) <> "_start_s"
}

/// Seconds per km from `5:00` (seconds need two digits) or `5` (whole minutes).
fn pace(text: String, what: String) -> Result(Int, String) {
  let seconds = case string.split(string.trim(text), ":") {
    [minutes] -> int.parse(minutes) |> result.map(fn(m) { m * 60 })
    [minutes, secs] ->
      case int.parse(minutes), int.parse(secs), string.length(secs) {
        Ok(m), Ok(s), 2 if m >= 0 && s >= 0 && s < 60 -> Ok(m * 60 + s)
        _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
  case seconds {
    Ok(s) if s >= fastest_s && s <= slowest_s -> Ok(s)
    _ ->
      Error(
        "The "
        <> what
        <> " must be a pace from "
        <> format(fastest_s)
        <> " to "
        <> format(slowest_s)
        <> " per km, like 5:30.",
      )
  }
}

/// Each start faster than the one before; `number` is the zone of the first one.
fn faster(starts: List(Int), number: Int) -> Result(Nil, #(Int, String)) {
  case starts {
    [a, b, ..rest] if b < a -> faster([b, ..rest], number + 1)
    [_, _, ..] ->
      Error(#(
        number + 1,
        "Pace zone "
          <> int.to_string(number + 1)
          <> " must start faster than pace zone "
          <> int.to_string(number)
          <> ".",
      ))
    _ -> Ok(Nil)
  }
}
