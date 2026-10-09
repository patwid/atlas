//// Reading a FIT activity file (Garmin's Flexible and Interoperable Data Transfer format,
//// https://developer.garmin.com/fit/protocol/). Pure. Only what an activity summary needs is read: the
//// `file_id`, the first `session` and the `lap` messages. Every other message is skipped by the size its
//// definition gives (ADR 0100).

import atlas/activity.{type Sport}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// A session's summary, with its laps in the order they were recorded.
pub type Summary {
  Summary(
    /// Identifies the file, so the same file is not imported twice: `<serial number>-<time created>`.
    file_id: String,
    /// Seconds since 1970, UTC.
    started_at: Int,
    sport: Sport,
    distance_m: Float,
    /// The timer time: stopped time is not counted.
    moving_time_s: Int,
    elapsed_time_s: Int,
    elevation_gain_m: Option(Int),
    avg_hr: Option(Int),
    max_hr: Option(Int),
    laps: List(Lap),
  )
}

pub type Lap {
  Lap(
    distance_m: Float,
    moving_time_s: Int,
    elapsed_time_s: Int,
    elevation_gain_m: Option(Int),
    avg_hr: Option(Int),
    max_hr: Option(Int),
  )
}

pub type Problem {
  /// Not a FIT file at all.
  NotFit
  /// A FIT file that ends early or whose messages do not add up.
  Damaged
  /// A FIT file of another kind, such as a course or a workout.
  NotAnActivity
  /// An activity file without a session summary.
  NoSession
}

pub fn problem_message(problem: Problem) -> String {
  case problem {
    NotFit -> "This is not a FIT file. Pick the .fit file of an activity."
    Damaged -> "This FIT file is damaged or incomplete."
    NotAnActivity ->
      "This FIT file holds no activity: it may be a course, a workout or settings."
    NoSession -> "This FIT file has no summary of the activity."
  }
}

/// Seconds between 1970-01-01 and FIT's epoch, 1989-12-31 00:00:00 UTC.
const fit_epoch = 631_065_600

const file_id_message = 0

const session_message = 18

const lap_message = 19

/// The `file_id` type of an activity file.
const activity_file = 4

pub fn decode(bytes: BitArray) -> Result(Summary, Problem) {
  case bytes {
    <<
      header_size,
      _protocol,
      _profile:little-size(16),
      data_size:little-size(32),
      ".FIT":utf8,
      rest:bytes,
    >>
      if header_size >= 12
    -> {
      // A 14-byte header ends with a CRC of its own.
      let extra = header_size - 12
      case rest {
        <<_:bytes-size(extra), data:bytes-size(data_size), _:bytes>> ->
          case messages(data, dict.new(), Found(None, None, [])) {
            Ok(found) -> summary(found)
            Error(problem) -> Error(problem)
          }
        _ -> Error(Damaged)
      }
    }
    _ -> Error(NotFit)
  }
}

// MESSAGES ----------------------------------------------------------------------------------------

type Field {
  Field(number: Int, size: Int, base_type: Int)
}

type Definition {
  Definition(
    global: Int,
    little_endian: Bool,
    fields: List(Field),
    /// The size of a data message of this definition, developer fields included.
    size: Int,
  )
}

/// A message's integer fields by number. Missing ("invalid") values are left out.
type Values =
  Dict(Int, Int)

type Found {
  Found(file_id: Option(Values), session: Option(Values), laps: List(Values))
}

/// Reads the messages one after another. Only this function calls itself, in tail position, so it compiles
/// to a loop: a file has thousands of messages, too many for one stack frame each.
fn messages(
  data: BitArray,
  definitions: Dict(Int, Definition),
  found: Found,
) -> Result(Found, Problem) {
  case data {
    <<>> -> Ok(Found(..found, laps: list.reverse(found.laps)))
    <<header, rest:bytes>> ->
      case message(header, rest, definitions, found) {
        Ok(#(rest, definitions, found)) -> messages(rest, definitions, found)
        Error(problem) -> Error(problem)
      }
    _ -> Error(Damaged)
  }
}

/// One message after its header byte: what remains, and the definitions and findings with it added.
fn message(
  header: Int,
  data: BitArray,
  definitions: Dict(Int, Definition),
  found: Found,
) -> Result(#(BitArray, Dict(Int, Definition), Found), Problem) {
  case int.bitwise_and(header, 0x80) != 0 {
    // A compressed timestamp header: a data message of local type 0-3.
    True ->
      data_message(
        int.bitwise_and(int.bitwise_shift_right(header, 5), 0x03),
        data,
        definitions,
        found,
      )
    False -> {
      let local = int.bitwise_and(header, 0x0F)
      case int.bitwise_and(header, 0x40) != 0 {
        True -> {
          let developer = int.bitwise_and(header, 0x20) != 0
          case definition(data, developer) {
            Ok(#(def, rest)) ->
              Ok(#(rest, dict.insert(definitions, local, def), found))
            Error(problem) -> Error(problem)
          }
        }
        False -> data_message(local, data, definitions, found)
      }
    }
  }
}

fn definition(
  data: BitArray,
  developer: Bool,
) -> Result(#(Definition, BitArray), Problem) {
  case data {
    <<_reserved, 0, global:little-size(16), count, rest:bytes>> ->
      definition_fields(rest, global, True, count, developer)
    <<_reserved, 1, global:big-size(16), count, rest:bytes>> ->
      definition_fields(rest, global, False, count, developer)
    _ -> Error(Damaged)
  }
}

fn definition_fields(
  data: BitArray,
  global: Int,
  little_endian: Bool,
  count: Int,
  developer: Bool,
) -> Result(#(Definition, BitArray), Problem) {
  case field_list(data, count, []) {
    Error(problem) -> Error(problem)
    Ok(#(fields, rest)) -> {
      let size = list.fold(fields, 0, fn(sum, field) { sum + field.size })
      case developer, rest {
        False, _ -> Ok(#(Definition(global, little_endian, fields, size), rest))
        True, <<developer_count, rest:bytes>> ->
          case field_list(rest, developer_count, []) {
            Ok(#(developer_fields, rest)) -> {
              // Developer fields are skipped, but their bytes count.
              let extra =
                list.fold(developer_fields, 0, fn(sum, field) {
                  sum + field.size
                })
              Ok(#(
                Definition(global, little_endian, fields, size + extra),
                rest,
              ))
            }
            Error(problem) -> Error(problem)
          }
        True, _ -> Error(Damaged)
      }
    }
  }
}

fn field_list(
  data: BitArray,
  count: Int,
  fields: List(Field),
) -> Result(#(List(Field), BitArray), Problem) {
  case count, data {
    0, _ -> Ok(#(list.reverse(fields), data))
    _, <<number, size, base_type, rest:bytes>> ->
      field_list(rest, count - 1, [Field(number, size, base_type), ..fields])
    _, _ -> Error(Damaged)
  }
}

fn data_message(
  local: Int,
  data: BitArray,
  definitions: Dict(Int, Definition),
  found: Found,
) -> Result(#(BitArray, Dict(Int, Definition), Found), Problem) {
  case dict.get(definitions, local) {
    Error(Nil) -> Error(Damaged)
    Ok(def) -> {
      let size = def.size
      case data {
        <<content:bytes-size(size), rest:bytes>> ->
          Ok(#(rest, definitions, keep(found, def, content)))
        _ -> Error(Damaged)
      }
    }
  }
}

/// Adds a message to what was found, if it is one of those needed. Only the first session counts.
fn keep(found: Found, def: Definition, content: BitArray) -> Found {
  case def.global {
    g if g == file_id_message && found.file_id == None ->
      Found(..found, file_id: Some(values(def, content)))
    g if g == session_message && found.session == None ->
      Found(..found, session: Some(values(def, content)))
    g if g == lap_message ->
      Found(..found, laps: [values(def, content), ..found.laps])
    _ -> found
  }
}

fn values(def: Definition, content: BitArray) -> Values {
  values_loop(def.fields, content, def.little_endian, dict.new())
}

fn values_loop(
  fields: List(Field),
  content: BitArray,
  little_endian: Bool,
  values: Values,
) -> Values {
  case fields {
    [] -> values
    [field, ..more] -> {
      let size = field.size
      case content {
        <<raw:bytes-size(size), rest:bytes>> -> {
          let values = case integer(raw, field.base_type, little_endian) {
            Ok(value) -> dict.insert(values, field.number, value)
            Error(Nil) -> values
          }
          values_loop(more, rest, little_endian, values)
        }
        _ -> values
      }
    }
  }
}

/// An integer field's value, or an error for a missing ("invalid") value, an array, or a field that is not an
/// integer (strings, floats, bytes, 64-bit numbers).
fn integer(
  raw: BitArray,
  base_type: Int,
  little_endian: Bool,
) -> Result(Int, Nil) {
  case int.bitwise_and(base_type, 0x1F) {
    // enum, uint8, uint8z
    0x00 | 0x02 -> unsigned(raw, 1, little_endian, 0xFF)
    0x0A -> unsigned(raw, 1, little_endian, 0)
    0x01 -> signed(raw, 1, little_endian)
    // uint16, uint16z, sint16
    0x04 -> unsigned(raw, 2, little_endian, 0xFFFF)
    0x0B -> unsigned(raw, 2, little_endian, 0)
    0x03 -> signed(raw, 2, little_endian)
    // uint32, uint32z, sint32
    0x06 -> unsigned(raw, 4, little_endian, 0xFFFF_FFFF)
    0x0C -> unsigned(raw, 4, little_endian, 0)
    0x05 -> signed(raw, 4, little_endian)
    _ -> Error(Nil)
  }
}

fn unsigned(
  raw: BitArray,
  bytes: Int,
  little_endian: Bool,
  invalid: Int,
) -> Result(Int, Nil) {
  case read(raw, bytes, little_endian) {
    Ok(value) if value != invalid -> Ok(value)
    _ -> Error(Nil)
  }
}

/// A two's-complement number. The invalid value is the largest positive one (`0x7F`, `0x7FFF`, ...).
fn signed(raw: BitArray, bytes: Int, little_endian: Bool) -> Result(Int, Nil) {
  let half = int.bitwise_shift_left(1, bytes * 8 - 1)
  case read(raw, bytes, little_endian) {
    Ok(value) if value == half - 1 -> Error(Nil)
    Ok(value) if value >= half -> Ok(value - 2 * half)
    Ok(value) -> Ok(value)
    Error(Nil) -> Error(Nil)
  }
}

fn read(raw: BitArray, bytes: Int, little_endian: Bool) -> Result(Int, Nil) {
  let bits = bytes * 8
  case little_endian, raw {
    True, <<value:little-size(bits)>> -> Ok(value)
    False, <<value:big-size(bits)>> -> Ok(value)
    _, _ -> Error(Nil)
  }
}

// SUMMARY -----------------------------------------------------------------------------------------

fn summary(found: Found) -> Result(Summary, Problem) {
  let file_id = option.unwrap(found.file_id, dict.new())
  case dict.get(file_id, 0), found.session {
    Ok(kind), _ if kind != activity_file -> Error(NotAnActivity)
    _, None -> Error(NoSession)
    _, Some(session) ->
      case first(session, [2, 253]) {
        Error(Nil) -> Error(NoSession)
        Ok(start) -> {
          let started_at = start + fit_epoch
          let moving = milliseconds(session, 8)
          let elapsed = milliseconds(session, 7)
          Ok(Summary(
            file_id: identity(file_id, started_at),
            started_at: started_at,
            sport: sport(
              option.from_result(dict.get(session, 5)),
              option.from_result(dict.get(session, 6)),
            ),
            distance_m: centimetres(session, 9),
            moving_time_s: case moving {
              0 -> elapsed
              _ -> moving
            },
            elapsed_time_s: case elapsed {
              0 -> moving
              _ -> elapsed
            },
            elevation_gain_m: option.from_result(dict.get(session, 22)),
            avg_hr: option.from_result(dict.get(session, 16)),
            max_hr: option.from_result(dict.get(session, 17)),
            laps: list.map(found.laps, lap),
          ))
        }
      }
  }
}

fn lap(values: Values) -> Lap {
  Lap(
    distance_m: centimetres(values, 9),
    moving_time_s: milliseconds(values, 8),
    elapsed_time_s: milliseconds(values, 7),
    elevation_gain_m: option.from_result(dict.get(values, 21)),
    avg_hr: option.from_result(dict.get(values, 15)),
    max_hr: option.from_result(dict.get(values, 16)),
  )
}

/// The serial number and creation time say which device wrote the file and when. Without them, the start does.
fn identity(file_id: Values, started_at: Int) -> String {
  case dict.get(file_id, 3), dict.get(file_id, 4) {
    Ok(serial), Ok(created) ->
      int.to_string(serial) <> "-" <> int.to_string(created)
    _, _ -> "start-" <> int.to_string(started_at)
  }
}

fn first(values: Values, numbers: List(Int)) -> Result(Int, Nil) {
  list.find_map(numbers, dict.get(values, _))
}

/// A time stored in thousandths of a second, rounded to whole seconds; 0 when missing.
fn milliseconds(values: Values, number: Int) -> Int {
  case dict.get(values, number) {
    Ok(ms) -> { ms + 500 } / 1000
    Error(Nil) -> 0
  }
}

/// A distance stored in hundredths of a metre, in metres; 0 when missing.
fn centimetres(values: Values, number: Int) -> Float {
  case dict.get(values, number) {
    Ok(cm) -> int.to_float(cm) /. 100.0
    Error(Nil) -> 0.0
  }
}

/// FIT's `sport` and `sub_sport` as one of Atlas's sports.
pub fn sport(sport: Option(Int), sub_sport: Option(Int)) -> Sport {
  case sport, sub_sport {
    // running; sub-sport trail
    Some(1), Some(3) -> activity.TrailRun
    Some(1), _ -> activity.Run
    Some(11), _ -> activity.Walk
    Some(17), _ -> activity.Hike
    // cycling, e-biking
    Some(2), _ | Some(21), _ -> activity.Ride
    Some(5), _ -> activity.Swim
    // training; sub-sport strength training
    Some(10), Some(20) -> activity.Strength
    _, _ -> activity.Other
  }
}
