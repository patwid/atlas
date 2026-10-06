//// Lactate zones as an explicit setting (ADR 0035): where each of the five zones starts, in mmol/L of blood
//// lactate. Until the athlete saves their own, the defaults are used: 1.0, 1.5, 2.5, 4.0 and 6.0 mmol/L.
//// Values have one decimal and are kept as whole tenths, so comparing them never meets float rounding. Pure.

import atlas/workout_form
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The lowest and highest value a zone may start at, in tenths of mmol/L (the server's limits: 0.1 to 30.0).
pub const min_tenths = 1

pub const max_tenths = 300

pub type LactateZones {
  /// `starts` has five entries, rising: where zones 1 to 5 begin, in tenths of mmol/L.
  LactateZones(starts: List(Int))
}

pub type Zone {
  /// `high` is `None` for zone 5, which has no upper end.
  Zone(number: Int, low: Int, high: Option(Int))
}

pub fn defaults() -> LactateZones {
  LactateZones([10, 15, 25, 40, 60])
}

/// The zones with both ends. A zone ends one tenth below the next one's start; zone 5 is open.
pub fn zones(settings: LactateZones) -> List(Zone) {
  let ends =
    list.append(
      list.map(list.drop(settings.starts, 1), fn(start) { Some(start - 1) }),
      [None],
    )
  list.zip(settings.starts, ends)
  |> list.index_map(fn(pair, index) { Zone(index + 1, pair.0, pair.1) })
}

/// The zone number (1-5) for a lactate value in tenths. `Error` below the start of zone 1.
pub fn zone_of(settings: LactateZones, tenths: Int) -> Result(Int, Nil) {
  zones(settings)
  |> list.find(fn(zone) {
    tenths >= zone.low
    && case zone.high {
      Some(high) -> tenths <= high
      None -> True
    }
  })
  |> result.map(fn(zone) { zone.number })
}

/// `1.5`, `4.0`: tenths as mmol/L with one decimal.
pub fn format(tenths: Int) -> String {
  int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10)
}

pub fn to_form(settings: LactateZones) -> List(String) {
  list.map(settings.starts, format)
}

/// Checks the five starts as typed (`2.5` or `2,5`): numbers from 0.1 to 30.0 with at most one decimal,
/// each zone starting above the one before.
pub fn parse(starts: List(String)) -> Result(LactateZones, String) {
  use values <- result.try(
    list.index_map(starts, fn(text, index) { value(text, index + 1) })
    |> result.all,
  )
  case list.length(values) == 5 {
    False -> Error("There must be five lactate zones.")
    True -> {
      use _ <- result.try(rising(values, 1))
      Ok(LactateZones(values))
    }
  }
}

/// The stored field for where zone `number` starts: `lactate_zone1_min` to `lactate_zone5_min`.
pub fn start_field(number: Int) -> String {
  "lactate_zone" <> int.to_string(number) <> "_min"
}

/// Tenths from a stored mmol/L value, rounded to the nearest tenth.
pub fn tenths_of(mmol: Float) -> Int {
  float.round(mmol *. 10.0)
}

pub fn to_mmol(tenths: Int) -> Float {
  int.to_float(tenths) /. 10.0
}

fn value(text: String, number: Int) -> Result(Int, String) {
  let problem =
    "The start of lactate zone "
    <> int.to_string(number)
    <> " must be a number from "
    <> format(min_tenths)
    <> " to "
    <> format(max_tenths)
    <> " with at most one decimal."
  case workout_form.parse_decimal(text) {
    Ok(mmol) -> {
      let tenths = tenths_of(mmol)
      let exact = float.absolute_value(mmol *. 10.0 -. int.to_float(tenths))
      case exact <. 0.000001 && tenths >= min_tenths && tenths <= max_tenths {
        True -> Ok(tenths)
        False -> Error(problem)
      }
    }
    Error(Nil) -> Error(problem)
  }
}

/// Each start above the one before; `number` is the zone of the first one.
fn rising(starts: List(Int), number: Int) -> Result(Nil, String) {
  case starts {
    [a, b, ..rest] if b > a -> rising([b, ..rest], number + 1)
    [_, _, ..] ->
      Error(
        "Lactate zone "
        <> int.to_string(number + 1)
        <> " must start higher than lactate zone "
        <> int.to_string(number)
        <> ".",
      )
    _ -> Ok(Nil)
  }
}
