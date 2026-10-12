//// Writing a workout as a FIT workout file (file type 5, https://developer.garmin.com/fit/protocol/), which a watch
//// loads to guide its wearer through the steps (ADR 0122). Pure. Messages are little-endian: a `file_id`, a `workout`
//// and one `workout_step` per step.

import atlas/watch_workout.{
  type End, type Intensity, type Step, type Target, Active, Cooldown, Distance,
  LapPress, Open, Pace, Recovery, Repeat, Step, Time, Warmup,
}
import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// Seconds between 1970-01-01 and FIT's epoch, 1989-12-31 00:00:00 UTC.
const fit_epoch = 631_065_600

/// The longest workout name written, in bytes: watches show only the start of it.
pub const max_name_bytes = 40

const protocol_version = 0x10

const profile_version = 2100

// Base types.
const enum = 0x00

const uint16 = 0x84

const uint32 = 0x86

const string_type = 0x07

const invalid_enum = 0xFF

const invalid_uint32 = 0xFFFF_FFFF

/// `name` is the workout's title, `created` the time of the export in seconds since 1970.
pub fn encode(name: String, steps: List(Step), created: Int) -> BitArray {
  let name = <<truncate(name):utf8, 0>>
  let data =
    bit_array.concat([
      definition(0, 0, [
        #(0, 1, enum),
        #(1, 2, uint16),
        #(2, 2, uint16),
        #(4, 4, uint32),
      ]),
      // A workout file, from a developer (manufacturer 255).
      <<
        0,
        5,
        255:little-size(16),
        0:little-size(16),
        { created - fit_epoch }:little-size(32),
      >>,
      definition(1, 26, [
        #(4, 1, enum),
        #(8, bit_array.byte_size(name), string_type),
        #(6, 2, uint16),
      ]),
      // Sport: running.
      <<1, 1, name:bits, { list.length(steps) }:little-size(16)>>,
      definition(2, 27, [
        #(254, 2, uint16),
        #(1, 1, enum),
        #(2, 4, uint32),
        #(3, 1, enum),
        #(4, 4, uint32),
        #(5, 4, uint32),
        #(6, 4, uint32),
        #(7, 1, enum),
      ]),
      ..list.index_map(steps, step)
    ])
  let header_start = <<
    14,
    protocol_version,
    profile_version:little-size(16),
    { bit_array.byte_size(data) }:little-size(32),
    ".FIT":utf8,
  >>
  let body = <<
    header_start:bits,
    { crc(header_start) }:little-size(16),
    data:bits,
  >>
  <<body:bits, { crc(body) }:little-size(16)>>
}

/// The file's name: the title in lower case, with a dash for every run of anything but ASCII letters and digits,
/// and `.fit`. `workout.fit` for a title without any.
pub fn file_name(title: String) -> String {
  let #(kept, _) =
    string.to_graphemes(string.lowercase(title))
    |> list.fold(#("", True), fn(acc, grapheme) {
      let #(kept, after_dash) = acc
      case string.contains("abcdefghijklmnopqrstuvwxyz0123456789", grapheme) {
        True -> #(kept <> grapheme, False)
        False if after_dash -> acc
        False -> #(kept <> "-", True)
      }
    })
  case kept {
    "" -> "workout.fit"
    _ ->
      case string.ends_with(kept, "-") {
        True -> string.drop_end(kept, 1)
        False -> kept
      }
      <> ".fit"
  }
}

/// The name, cut to whole characters within `max_name_bytes`. A workout without a title is called Workout.
fn truncate(name: String) -> String {
  case string.trim(name) {
    "" -> "Workout"
    name ->
      string.to_graphemes(name)
      |> list.fold_until("", fn(kept, grapheme) {
        let longer = kept <> grapheme
        case string.byte_size(longer) <= max_name_bytes {
          True -> list.Continue(longer)
          False -> list.Stop(kept)
        }
      })
  }
}

/// A definition message for local type `local` of the message `global`, with fields as number, size and base type.
fn definition(
  local: Int,
  global: Int,
  fields: List(#(Int, Int, Int)),
) -> BitArray {
  list.fold(
    fields,
    <<{ 0x40 + local }, 0, 0, global:little-size(16), { list.length(fields) }>>,
    fn(bytes, field) { <<bytes:bits, field.0, field.1, field.2>> },
  )
}

fn step(step: Step, index: Int) -> BitArray {
  let #(
    duration_type,
    duration_value,
    target_type,
    target_value,
    low,
    high,
    intensity,
  ) = case step {
    Repeat(from, times) -> #(
      6,
      from,
      invalid_enum,
      times,
      invalid_uint32,
      invalid_uint32,
      invalid_enum,
    )
    Step(intensity, end, target) -> {
      let #(duration_type, duration_value) = duration(end)
      let #(target_type, target_value, low, high) = target_values(target)
      #(
        duration_type,
        duration_value,
        target_type,
        target_value,
        low,
        high,
        intensity_value(intensity),
      )
    }
  }
  <<
    2, index:little-size(16), duration_type, duration_value:little-size(32),
    target_type, target_value:little-size(32), low:little-size(32),
    high:little-size(32), intensity,
  >>
}

/// The duration type (time, distance or open) and its value, in thousandths of a second or hundredths of a metre.
fn duration(end: End) -> #(Int, Int) {
  case end {
    Time(seconds) -> #(0, seconds * 1000)
    Distance(metres) -> #(1, float.round(metres *. 100.0))
    LapPress -> #(5, invalid_uint32)
  }
}

/// The target type (speed or open), its value (0 for a custom range) and the range in thousandths of a metre per
/// second.
fn target_values(target: Target) -> #(Int, Int, Int, Int) {
  case target {
    Pace(slowest, fastest) -> #(0, 0, speed(slowest), speed(fastest))
    Open -> #(2, 0, invalid_uint32, invalid_uint32)
  }
}

/// A pace in seconds per km as a speed in mm/s.
fn speed(pace_s: Int) -> Int {
  float.round(1_000_000.0 /. int.to_float(int.max(pace_s, 1)))
}

fn intensity_value(intensity: Intensity) -> Int {
  case intensity {
    Active -> 0
    Warmup -> 2
    Cooldown -> 3
    Recovery -> 4
  }
}

// CRC ---------------------------------------------------------------------------------------------

/// FIT's 16-bit CRC (CRC-16/ARC). Over a whole file, its own CRC included, it is 0.
pub fn crc(bytes: BitArray) -> Int {
  crc_loop(bytes, 0)
}

fn crc_loop(bytes: BitArray, crc: Int) -> Int {
  case bytes {
    <<byte, rest:bytes>> -> {
      let crc = crc_nibble(crc, int.bitwise_and(byte, 0x0F))
      crc_loop(rest, crc_nibble(crc, int.bitwise_shift_right(byte, 4)))
    }
    _ -> crc
  }
}

fn crc_nibble(crc: Int, nibble: Int) -> Int {
  let shifted = int.bitwise_and(int.bitwise_shift_right(crc, 4), 0x0FFF)
  int.bitwise_exclusive_or(
    int.bitwise_exclusive_or(shifted, crc_table(int.bitwise_and(crc, 0x0F))),
    crc_table(nibble),
  )
}

fn crc_table(index: Int) -> Int {
  case index {
    0 -> 0x0000
    1 -> 0xCC01
    2 -> 0xD801
    3 -> 0x1400
    4 -> 0xF001
    5 -> 0x3C00
    6 -> 0x2800
    7 -> 0xE401
    8 -> 0xA001
    9 -> 0x6C00
    10 -> 0x7800
    11 -> 0xB401
    12 -> 0x5000
    13 -> 0x9C01
    14 -> 0x8801
    _ -> 0x4400
  }
}
