//// Heart-rate zones as an explicit setting (ADR 0034): a maximum heart rate and where each of the five
//// zones starts, in beats per minute. Until the athlete saves their own, the defaults are used: zones
//// from 50, 60, 70, 80 and 90 percent of a maximum of 190. Pure: parsing and checking.

import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub const default_max_hr = 190

/// The lowest and highest heart rate a zone boundary or the maximum may have (the server's limits).
pub const min_bpm = 30

pub const max_bpm = 250

pub type HrZones {
  /// `starts` has five entries, rising, all at most `max_hr`: where zones 1 to 5 begin.
  HrZones(max_hr: Int, starts: List(Int))
}

pub type Zone {
  Zone(number: Int, low: Int, high: Int)
}

/// What the zones form holds: the text of the maximum and of the five starts.
pub type Form {
  Form(max_hr: String, starts: List(String))
}

/// The default zones for a maximum: starts at 50, 60, 70, 80 and 90 percent of it, rounded down.
pub fn defaults(max_hr: Int) -> HrZones {
  HrZones(
    max_hr,
    list.map([50, 60, 70, 80, 90], fn(percent) { max_hr * percent / 100 }),
  )
}

/// The zones with both ends. They do not overlap: a zone ends one beat below the next one's start,
/// and zone 5 ends at the maximum.
pub fn zones(settings: HrZones) -> List(Zone) {
  let ends =
    list.append(
      list.map(list.drop(settings.starts, 1), fn(start) { start - 1 }),
      [settings.max_hr],
    )
  list.zip(settings.starts, ends)
  |> list.index_map(fn(pair, index) { Zone(index + 1, pair.0, pair.1) })
}

/// The zone number (1-5) for a heart rate. Rates above the maximum count as zone 5.
/// `Error` below the start of zone 1.
pub fn zone_of(settings: HrZones, hr: Int) -> Result(Int, Nil) {
  case hr > settings.max_hr {
    True -> Ok(list.length(settings.starts))
    False ->
      zones(settings)
      |> list.find(fn(zone) { hr >= zone.low && hr <= zone.high })
      |> result.map(fn(zone) { zone.number })
  }
}

pub fn to_form(settings: HrZones) -> Form {
  Form(int.to_string(settings.max_hr), list.map(settings.starts, int.to_string))
}

/// The form with the zones worked out again from the maximum it holds (the default percentages).
/// `Error` when the maximum is not usable.
pub fn fill_from_max(form: Form) -> Result(Form, String) {
  bpm(form.max_hr, "maximum heart rate")
  |> result.map(fn(max_hr) { to_form(defaults(max_hr)) })
}

/// Checks the form: whole numbers from 30 to 250, each zone starting above the one before, and
/// zone 5 starting at most at the maximum.
pub fn parse(form: Form) -> Result(HrZones, String) {
  parse_at(form) |> result.map_error(fn(problem) { problem.1 })
}

/// `parse`, with the input each problem is about (ADR 0077): 0 for the maximum, 1 to 5 for a zone's start, -1 for
/// the whole form.
pub fn parse_at(form: Form) -> Result(HrZones, #(Int, String)) {
  use max_hr <- result.try(at(bpm(form.max_hr, "maximum heart rate"), 0))
  use starts <- result.try(
    list.index_map(form.starts, fn(text, index) {
      at(bpm(text, "start of zone " <> int.to_string(index + 1)), index + 1)
    })
    |> result.all,
  )
  case list.length(starts) == 5 {
    False -> Error(#(-1, "There must be five zones."))
    True -> {
      use _ <- result.try(rising(starts, 1))
      case list.last(starts) {
        Ok(last) if last > max_hr ->
          Error(#(5, "Zone 5 must start at or below the maximum heart rate."))
        _ -> Ok(HrZones(max_hr, starts))
      }
    }
  }
}

fn at(parsed: Result(a, String), input: Int) -> Result(a, #(Int, String)) {
  result.map_error(parsed, fn(message) { #(input, message) })
}

/// Each start above the one before; `number` is the zone of the first one.
fn rising(starts: List(Int), number: Int) -> Result(Nil, #(Int, String)) {
  case starts {
    [a, b, ..rest] if b > a -> rising([b, ..rest], number + 1)
    [_, _, ..] ->
      Error(#(
        number + 1,
        "Zone "
          <> int.to_string(number + 1)
          <> " must start higher than zone "
          <> int.to_string(number)
          <> ".",
      ))
    _ -> Ok(Nil)
  }
}

pub fn start_field(number: Int) -> String {
  "hr_zone" <> int.to_string(number) <> "_min"
}

fn bpm(text: String, what: String) -> Result(Int, String) {
  case int.parse(string.trim(text)) {
    Ok(n) if n >= min_bpm && n <= max_bpm -> Ok(n)
    _ ->
      Error(
        "The "
        <> what
        <> " must be a whole number from "
        <> int.to_string(min_bpm)
        <> " to "
        <> int.to_string(max_bpm)
        <> ".",
      )
  }
}
