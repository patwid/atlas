import atlas/activity
import atlas/fit.{Lap, Summary}
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}

// A small FIT writer, so each test says which messages its file holds.

const enum = 0x00

const uint8 = 0x02

const uint16 = 0x84

const uint32 = 0x86

const uint32z = 0x8C

const string = 0x07

/// 2025-09-28 13:20:00 UTC in FIT's time (seconds since 1989-12-31).
const start = 1_128_000_000

const start_unix = 1_759_065_600

fn file(records: BitArray) -> BitArray {
  let size = bit_array.byte_size(records)
  <<
    14, 0x20, 2132:little-size(16), size:little-size(32), ".FIT":utf8,
    0:size(16), records:bits, 0:size(16),
  >>
}

/// A little-endian definition of `fields`: number, size, base type.
fn define(local: Int, global: Int, fields: List(#(Int, Int, Int))) -> BitArray {
  let header = 0x40 + local
  let count = list.length(fields)
  <<header, 0, 0, global:little-size(16), count>>
  |> field_bytes(fields)
}

fn define_big(
  local: Int,
  global: Int,
  fields: List(#(Int, Int, Int)),
) -> BitArray {
  let header = 0x40 + local
  let count = list.length(fields)
  <<header, 0, 1, global:big-size(16), count>>
  |> field_bytes(fields)
}

fn field_bytes(start: BitArray, fields: List(#(Int, Int, Int))) -> BitArray {
  list.fold(fields, start, fn(bytes, f) { <<bytes:bits, f.0, f.1, f.2>> })
}

const file_id_fields = [
  #(0, 1, enum),
  #(3, 4, uint32z),
  #(4, 4, uint32),
]

fn file_id(kind: Int) -> BitArray {
  <<
    define(0, 0, file_id_fields):bits,
    0,
    kind,
    3_456_789_012:little-size(32),
    start:little-size(32),
  >>
}

const session_fields = [
  #(2, 4, uint32),
  #(5, 1, enum),
  #(6, 1, enum),
  #(7, 4, uint32),
  #(8, 4, uint32),
  #(9, 4, uint32),
  #(16, 1, uint8),
  #(17, 1, uint8),
  #(22, 2, uint16),
]

fn session(sport: Int, sub_sport: Int, avg_hr: Int, ascent: Int) -> BitArray {
  <<
    define(1, 18, session_fields):bits,
    1,
    start:little-size(32),
    sport,
    sub_sport,
    // elapsed 50:00.4, timer 48:20.6, 10.23456 km
    3_000_400:little-size(32),
    2_900_600:little-size(32),
    1_023_456:little-size(32),
    avg_hr,
    171,
    ascent:little-size(16),
  >>
}

const lap_fields = [
  #(7, 4, uint32),
  #(8, 4, uint32),
  #(9, 4, uint32),
  #(15, 1, uint8),
  #(16, 1, uint8),
  #(21, 2, uint16),
]

fn lap(
  local: Int,
  elapsed_ms: Int,
  timer_ms: Int,
  cm: Int,
  hr: Int,
) -> BitArray {
  <<
    local, elapsed_ms:little-size(32), timer_ms:little-size(32),
    cm:little-size(32), hr, 0xFF, 0xFFFF:little-size(16),
  >>
}

fn run_file() -> BitArray {
  file(<<
    file_id(4):bits,
    define(2, 19, lap_fields):bits,
    lap(2, 1_500_000, 1_450_000, 500_000, 150):bits,
    lap(2, 1_500_400, 1_450_600, 523_456, 160):bits,
    session(1, 0, 155, 87):bits,
  >>)
}

pub fn a_run_is_read_with_its_laps_test() {
  assert fit.decode(run_file())
    == Ok(
      Summary(
        file_id: "3456789012-1128000000",
        started_at: start_unix,
        sport: activity.Run,
        distance_m: 10_234.56,
        moving_time_s: 2901,
        elapsed_time_s: 3000,
        elevation_gain_m: Some(87),
        avg_hr: Some(155),
        max_hr: Some(171),
        laps: [
          Lap(5000.0, 1450, 1500, None, Some(150), None),
          Lap(5234.56, 1451, 1500, None, Some(160), None),
        ],
      ),
    )
}

pub fn a_twelve_byte_header_is_read_too_test() {
  let records = <<file_id(4):bits, session(1, 0, 155, 87):bits>>
  let size = bit_array.byte_size(records)
  let short = <<
    12, 0x10, 2132:little-size(16), size:little-size(32), ".FIT":utf8,
    records:bits, 0:size(16),
  >>
  let assert Ok(summary) = fit.decode(short)
  assert summary.started_at == start_unix
}

pub fn big_endian_messages_are_read_test() {
  let records = <<
    define_big(0, 18, [#(2, 4, uint32), #(9, 4, uint32), #(22, 2, uint16)]):bits,
    0,
    start:big-size(32),
    1_000_000:big-size(32),
    120:big-size(16),
  >>
  let assert Ok(summary) = fit.decode(file(records))
  assert summary.started_at == start_unix
  assert summary.distance_m == 10_000.0
  assert summary.elevation_gain_m == Some(120)
}

pub fn other_messages_developer_fields_and_compressed_headers_are_skipped_test() {
  let records = <<
    file_id(4):bits,
    // A record message (20) with a string, defined (0x63: local type 3, with developer fields) with one
    // developer field of 3 bytes.
    0x63,
    0,
    0,
    20:little-size(16),
    2,
    253,
    4,
    uint32,
    50,
    5,
    string,
    1,
    0,
    3,
    0,
    // ...as a normal data message and as one with a compressed timestamp header (0xE5: local type 3).
    3,
    start:little-size(32),
    "hello":utf8,
    1,
    2,
    3,
    0xE5,
    start:little-size(32),
    "again":utf8,
    4,
    5,
    6,
    session(1, 0, 155, 87):bits,
  >>
  let assert Ok(summary) = fit.decode(file(records))
  assert summary.avg_hr == Some(155)
}

pub fn invalid_values_are_missing_test() {
  let assert Ok(summary) =
    fit.decode(file(<<file_id(4):bits, session(1, 0, 0xFF, 0xFFFF):bits>>))
  assert summary.avg_hr == None
  assert summary.elevation_gain_m == None
  assert summary.max_hr == Some(171)
}

pub fn only_the_first_session_counts_test() {
  let assert Ok(summary) =
    fit.decode(
      file(<<
        file_id(4):bits,
        session(1, 0, 155, 87):bits,
        session(2, 0, 120, 10):bits,
      >>),
    )
  assert summary.sport == activity.Run
}

pub fn without_a_serial_number_the_start_identifies_the_file_test() {
  let assert Ok(summary) = fit.decode(file(session(1, 0, 155, 87)))
  assert summary.file_id == "start-1759065600"
}

pub fn a_course_is_not_an_activity_test() {
  assert fit.decode(file(<<file_id(6):bits, session(1, 0, 155, 87):bits>>))
    == Error(fit.NotAnActivity)
}

pub fn an_activity_needs_a_session_test() {
  assert fit.decode(file(file_id(4))) == Error(fit.NoSession)
}

pub fn other_files_are_not_fit_test() {
  assert fit.decode(<<"<?xml version=\"1.0\"?><gpx>":utf8>>)
    == Error(fit.NotFit)
  assert fit.decode(<<>>) == Error(fit.NotFit)
}

pub fn a_cut_off_file_is_damaged_test() {
  let whole = run_file()
  let assert Ok(cut) =
    bit_array.slice(whole, 0, bit_array.byte_size(whole) - 20)
  assert fit.decode(cut) == Error(fit.Damaged)
}

pub fn a_data_message_without_a_definition_is_damaged_test() {
  assert fit.decode(file(<<5, 1, 2, 3>>)) == Error(fit.Damaged)
}

pub fn sports_map_to_atlas_sports_test() {
  assert fit.sport(Some(1), Some(0)) == activity.Run
  assert fit.sport(Some(1), Some(3)) == activity.TrailRun
  assert fit.sport(Some(11), None) == activity.Walk
  assert fit.sport(Some(17), None) == activity.Hike
  assert fit.sport(Some(2), Some(7)) == activity.Ride
  assert fit.sport(Some(5), Some(17)) == activity.Swim
  assert fit.sport(Some(10), Some(20)) == activity.Strength
  assert fit.sport(Some(10), Some(0)) == activity.Other
  assert fit.sport(None, None) == activity.Other
}

pub fn a_file_with_many_messages_does_not_run_out_of_stack_test() {
  let record = <<
    define(4, 20, [#(253, 4, uint32)]):bits,
    4,
    start:little-size(32),
  >>
  let records =
    list.repeat(<<4, start:little-size(32)>>, 50_000)
    |> list.fold(record, fn(bytes, more) { <<bytes:bits, more:bits>> })
  let assert Ok(summary) =
    fit.decode(file(<<records:bits, session(1, 0, 155, 87):bits>>))
  assert summary.sport == activity.Run
}
