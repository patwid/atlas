import atlas/fit
import atlas/fit_workout
import atlas/watch_workout.{
  Active, Cooldown, Distance, LapPress, Open, Pace, Recovery, Repeat, Step, Time,
  Warmup,
}
import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/string

/// 2026-10-12 08:00:00 UTC.
const created = 1_791_792_000

const steps = [
  Step(Warmup, Time(900), Pace(420, 388)),
  Step(Active, Distance(400.0), Pace(318, 298)),
  Step(Recovery, Time(60), Open),
  Repeat(1, 6),
  Step(Cooldown, LapPress, Open),
]

pub fn the_crc_is_fits_crc_16_test() {
  let assert 0xBB3D = fit_workout.crc(<<"123456789":utf8>>)
}

pub fn a_file_ends_with_its_crc_and_has_a_fourteen_byte_header_test() {
  let bytes = fit_workout.encode("Track", steps, created)
  let assert 0 = fit_workout.crc(bytes)
  let assert <<header:bytes-size(14), _:bytes>> = bytes
  let assert 0 = fit_workout.crc(header)
  let assert <<14, _, _:size(16), size:little-size(32), ".FIT":utf8, _:bytes>> =
    bytes
  let assert True = size == bit_array.byte_size(bytes) - 16
}

pub fn a_workout_file_is_not_an_activity_test() {
  let assert Error(fit.NotAnActivity) =
    fit.decode(fit_workout.encode("Track", steps, created))
}

pub fn the_messages_read_back_test() {
  let assert Ok([#(0, file_id), #(26, workout), ..step_messages]) =
    fit.read_messages(fit_workout.encode("Track", steps, created))
  // A workout file, from a developer, created at FIT's time.
  let assert Ok(5) = dict.get(file_id, 0)
  let assert Ok(255) = dict.get(file_id, 1)
  let assert Ok(1_160_726_400) = dict.get(file_id, 4)
  // Running, five steps.
  let assert Ok(1) = dict.get(workout, 4)
  let assert Ok(5) = dict.get(workout, 6)
  let assert [
    #(27, warmup),
    #(27, rep),
    #(27, recovery),
    #(27, repeat),
    #(27, cooldown),
  ] = step_messages
  let fields = fn(values, numbers) {
    list.map(numbers, fn(n) { dict.get(values, n) })
  }
  let all = [254, 1, 2, 3, 4, 5, 6, 7]
  // Index, duration type and value, target type and value, low and high speed in mm/s, intensity.
  let assert [
    Ok(0),
    Ok(0),
    Ok(900_000),
    Ok(0),
    Ok(0),
    Ok(2381),
    Ok(2577),
    Ok(2),
  ] = fields(warmup, all)
  let assert [Ok(1), Ok(1), Ok(40_000), Ok(0), Ok(0), Ok(3145), Ok(3356), Ok(0)] =
    fields(rep, all)
  let assert [
    Ok(2),
    Ok(0),
    Ok(60_000),
    Ok(2),
    Ok(0),
    Error(Nil),
    Error(Nil),
    Ok(4),
  ] = fields(recovery, all)
  // Repeat from step 1, six times in all.
  let assert [
    Ok(3),
    Ok(6),
    Ok(1),
    Error(Nil),
    Ok(6),
    Error(Nil),
    Error(Nil),
    Error(Nil),
  ] = fields(repeat, all)
  let assert [
    Ok(4),
    Ok(5),
    Error(Nil),
    Ok(2),
    Ok(0),
    Error(Nil),
    Error(Nil),
    Ok(3),
  ] = fields(cooldown, all)
}

pub fn the_name_is_kept_whole_or_cut_at_a_character_test() {
  let assert True = name_of(fit_workout.encode("Track", [], created)) == "Track"
  let assert True = name_of(fit_workout.encode("  ", [], created)) == "Workout"
  // 39 ASCII bytes and a two-byte character: the character does not fit.
  let long = string.repeat("a", 39) <> "é and more"
  let assert True =
    name_of(fit_workout.encode(long, [], created)) == string.repeat("a", 39)
}

/// The workout's name, read from the bytes after its definition (`fit.read_messages` keeps only integers).
fn name_of(bytes: BitArray) -> String {
  let assert <<_:bytes-size(14), rest:bytes>> = bytes
  // file_id: definition of 4 fields (6 + 12 bytes) and 10 bytes of data; then the workout's definition.
  let assert <<_:bytes-size(28), 0x41, 0, 0, 26:little-size(16), 3, rest:bytes>> =
    rest
  let assert <<
    4,
    1,
    0,
    8,
    size,
    7,
    6,
    2,
    0x84,
    1,
    1,
    name:bytes-size(size),
    _:bytes,
  >> = rest
  let assert Ok(text) = bit_array.slice(name, 0, size - 1)
  let assert Ok(text) = bit_array.to_string(text)
  text
}

pub fn the_file_is_named_after_the_title_test() {
  let assert "6-800-m-zone-4.fit" = fit_workout.file_name("6 × 800 m (Zone 4)")
  let assert "long-run.fit" = fit_workout.file_name("  Long run! ")
  let assert "workout.fit" = fit_workout.file_name("…")
}
