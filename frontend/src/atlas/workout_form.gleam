//// The workout form: parsing what the user typed (a week, a day, "5,5" km, "1:30" hours) and choosing
//// which fields to write. Pure. Limits follow the server (ADR 0009).

import atlas/outbox
import atlas/pace_zones.{type PaceZones}
import atlas/plan.{
  type GoalPace, type Intervals, type Kind, type Segment, type Workout, GoalPace,
  Intervals,
}
import atlas/units
import gleam/dict
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const max_title = 200

pub const max_description = 5000

/// Plans can run for a year or so; the limit keeps typing mistakes (week 5000) out.
pub const max_weeks = 60

const max_distance_km = 1000.0

const max_duration_seconds = 172_800

pub const max_reps = 100

const max_rep_distance_m = 20_000.0

const max_rep_seconds = 3600

const max_warmup_distance_m = 50_000.0

const max_warmup_seconds = 18_000

/// The training zones of the athlete's settings: five of each kind (ADR 0034, 0035, 0036).
pub const zones = [1, 2, 3, 4, 5]

pub type Form {
  Form(
    /// 1-based, as typed.
    week: String,
    /// 1-7, the day of the plan's week.
    day: String,
    title: String,
    kind: Kind,
    distance_km: String,
    duration: String,
    description: String,
    /// The parts of an interval workout, as typed; only read when the kind is intervals (ADR 0104, 0116). A race
    /// reads only the warm-up and cool-down (ADR 0119).
    warmup: SegmentForm,
    /// At least one, so a new interval workout shows the fields of its first set.
    sets: List(SetForm),
    cooldown: SegmentForm,
    /// The target zone, `""` for none (ADR 0105).
    zone: String,
    /// Which of distance and duration was typed last: the other is worked out from the zone (ADR 0106).
    target_typed: Typed,
    /// The plan's first day: days of week 1 before it cannot be chosen (ADR 0108).
    first_day: Int,
    /// The race goals a rep can be run at (ADR 0118): the plan's athlete's, and any a rep was saved with that are
    /// no longer among them.
    goals: List(RaceGoal),
    error: Option(String),
  )
}

/// A race goal a rep can be run at a share of (ADR 0115, 0118).
pub type RaceGoal {
  RaceGoal(id: String, distance_m: Float, time_s: Int)
}

/// A warm-up, a cool-down, or a rep or recovery of a set, as typed (ADR 0116). A warm-up's and a cool-down's
/// distance is in kilometres and its time in minutes, like the workout's; a rep's and a recovery's in metres and
/// seconds (`90`, `1:30`). A rep can be run at an intensity of a race goal instead of a zone: `goal` is its ID, `""`
/// for none, and `intensity` the percentage of its speed (ADR 0118).
pub type SegmentForm {
  SegmentForm(
    zone: String,
    distance: String,
    time: String,
    typed: Typed,
    goal: String,
    intensity: String,
  )
}

pub const blank_segment = SegmentForm("", "", "", NeitherTyped, "", "")

pub type SetForm {
  SetForm(reps: String, work: SegmentForm, recovery: SegmentForm)
}

pub const blank_set = SetForm("", blank_segment, blank_segment)

/// A segment of the form; sets are counted from 0.
pub type Part {
  Warmup
  Cooldown
  Work(set: Int)
  Recovery(set: Int)
}

pub type SegmentField {
  ZoneField
  DistanceField
  TimeField
  GoalField
  IntensityField
  /// Whether a rep is run at a zone (`"zone"`) or at a race goal (`"goal"`) (ADR 0120).
  TargetField
}

/// What a rep is run at (ADR 0120): a zone, or an intensity of a race goal. A rep has a race goal exactly when it is
/// run at one, so this is read from its `goal`.
pub fn target(segment: SegmentForm) -> String {
  case string.trim(segment.goal) {
    "" -> "zone"
    _ -> "goal"
  }
}

/// Which of a distance and a time the user typed last (ADR 0106).
pub type Typed {
  /// Neither since the form opened: nothing is worked out, so a stored workout keeps its values.
  NeitherTyped
  DistanceTyped
  TimeTyped
}

/// What a form says after validation. A distance or duration of 0 means "no target".
pub type Valid {
  Valid(
    day_index: Int,
    title: String,
    kind: Kind,
    distance_m: Float,
    duration_s: Int,
    description: String,
    /// `None` unless the workout is an interval workout with parts, or a race with a warm-up or cool-down.
    intervals: Option(Intervals),
    /// 1-5, 0 for none (ADR 0105).
    zone: Int,
  )
}

/// A workout as stored, with the fields the domain type does not carry.
pub type Row {
  Row(
    workout: Workout,
    description: String,
    intervals: Option(Intervals),
    zone: Int,
    updated: String,
  )
}

/// The workout as planned: an interval workout's distance and duration are those of its parts (ADR 0130).
pub fn planned(row: Row) -> plan.Workout {
  plan.with_totals(row.workout, row.intervals)
}

pub fn empty_for(week: Int, day: Int) -> Form {
  Form(
    int.to_string(week),
    int.to_string(day),
    "",
    plan.Run,
    "",
    "",
    "",
    blank_segment,
    [blank_set],
    blank_segment,
    "",
    NeitherTyped,
    0,
    [],
    None,
  )
}

pub fn from_row(row: Row) -> Form {
  let w = row.workout
  Form(
    week: int.to_string(w.day_index / 7 + 1),
    day: int.to_string(w.day_index % 7 + 1),
    title: w.title,
    kind: w.kind,
    distance_km: case w.distance_m {
      Some(m) -> format_km(m)
      None -> ""
    },
    duration: case w.duration_s {
      Some(s) -> format_duration(s)
      None -> ""
    },
    description: row.description,
    warmup: case row.intervals {
      Some(i) -> segment_form(i.warmup, Warmup)
      None -> blank_segment
    },
    sets: case row.intervals {
      Some(Intervals(sets: [_, ..] as sets, ..)) ->
        list.map(sets, fn(set) {
          SetForm(
            int.to_string(set.reps),
            segment_form(set.work, Work(0)),
            segment_form(set.recovery, Recovery(0)),
          )
        })
      _ -> [blank_set]
    },
    cooldown: case row.intervals {
      Some(i) -> segment_form(i.cooldown, Cooldown)
      None -> blank_segment
    },
    zone: case row.zone {
      0 -> ""
      n -> int.to_string(n)
    },
    target_typed: NeitherTyped,
    first_day: 0,
    goals: case row.intervals {
      Some(i) ->
        list.filter_map(i.sets, fn(set) {
          case set.work.goal {
            Some(g) -> Ok(RaceGoal(g.goal_id, g.distance_m, g.time_s))
            None -> Error(Nil)
          }
        })
        |> list.unique
      None -> []
    },
    error: None,
  )
}

/// The form with the race goals its reps can be run at (ADR 0118): `goals`, then those a rep was saved with that
/// are not among them, so a changed goal is read as it is now and a deleted one can still be kept.
pub fn with_goals(form: Form, goals: List(RaceGoal)) -> Form {
  let gone =
    list.filter(form.goals, fn(kept) {
      !list.any(goals, fn(goal) { goal.id == kept.id })
    })
  Form(..form, goals: list.append(goals, gone))
}

/// `10 km in 45:00`
pub fn goal_label(goal: RaceGoal) -> String {
  format_km(goal.distance_m) <> " km in " <> units.format_duration(goal.time_s)
}

fn segment_form(segment: Segment, part: Part) -> SegmentForm {
  SegmentForm(
    zone: case segment.zone {
      0 -> ""
      n -> int.to_string(n)
    },
    distance: case segment.distance_m >. 0.0, is_long(part) {
      False, _ -> ""
      True, True -> format_km(segment.distance_m)
      True, False -> int.to_string(float.round(segment.distance_m))
    },
    time: case segment.duration_s > 0, is_long(part) {
      False, _ -> ""
      True, True -> format_duration(segment.duration_s)
      True, False -> format_rep_time(segment.duration_s)
    },
    typed: NeitherTyped,
    goal: case segment.goal {
      Some(g) -> g.goal_id
      None -> ""
    },
    intensity: case segment.goal {
      Some(g) -> int.to_string(g.intensity)
      None -> ""
    },
  )
}

/// A warm-up and a cool-down are typed in kilometres and minutes, like a workout; reps and recoveries in metres
/// and seconds (ADR 0116).
fn is_long(part: Part) -> Bool {
  case part {
    Warmup | Cooldown -> True
    Work(_) | Recovery(_) -> False
  }
}

// THE PARTS OF AN INTERVAL WORKOUT (ADR 0116) -------------------------------------------------------

pub fn segment(form: Form, part: Part) -> SegmentForm {
  case part {
    Warmup -> form.warmup
    Cooldown -> form.cooldown
    Work(index) -> set_at(form, index).work
    Recovery(index) -> set_at(form, index).recovery
  }
}

fn set_at(form: Form, index: Int) -> SetForm {
  case list.drop(form.sets, index) {
    [set, ..] -> set
    [] -> blank_set
  }
}

/// A zone, race goal, intensity, distance or time of a part was typed: the other of its distance and time is worked
/// out from its zone, or from its race goal at its intensity (ADR 0118). A zone and a race goal exclude each other:
/// choosing one clears the other, and a race goal starts at 100 %. Choosing to run a rep at a race goal takes the
/// first of the form's goals (ADR 0120).
pub fn edit_segment(
  form: Form,
  part: Part,
  field: SegmentField,
  text: String,
  zones: PaceZones,
) -> Form {
  let edited = set_segment(form, part, field, text)
  let filled =
    fill_segment(
      segment(edited, part),
      is_long(part),
      segment_pace(segment(edited, part), form.goals, zones),
    )
  put_segment(edited, part, filled)
}

/// A field of a part as typed, with nothing worked out: an activity's parts were measured, not planned (ADR 0121).
pub fn set_segment(
  form: Form,
  part: Part,
  field: SegmentField,
  text: String,
) -> Form {
  let current = segment(form, part)
  let edited = case field {
    ZoneField if text == "" -> SegmentForm(..current, zone: text)
    ZoneField -> SegmentForm(..current, zone: text, goal: "", intensity: "")
    DistanceField ->
      SegmentForm(..current, distance: text, typed: DistanceTyped)
    TimeField -> SegmentForm(..current, time: text, typed: TimeTyped)
    GoalField if text == "" -> SegmentForm(..current, goal: "", intensity: "")
    GoalField ->
      SegmentForm(
        ..current,
        zone: "",
        goal: text,
        intensity: case string.trim(current.intensity) {
          "" -> "100"
          intensity -> intensity
        },
      )
    IntensityField -> SegmentForm(..current, intensity: text)
    TargetField ->
      case text, target(current), form.goals {
        "goal", "zone", [first, ..] ->
          SegmentForm(..current, zone: "", goal: first.id, intensity: "100")
        "zone", "goal", _ -> SegmentForm(..current, goal: "", intensity: "")
        _, _, _ -> current
      }
  }
  put_segment(form, part, edited)
}

fn put_segment(form: Form, part: Part, segment: SegmentForm) -> Form {
  case part {
    Warmup -> Form(..form, warmup: segment)
    Cooldown -> Form(..form, cooldown: segment)
    Work(index) ->
      update_set(form, index, fn(set) { SetForm(..set, work: segment) })
    Recovery(index) ->
      update_set(form, index, fn(set) { SetForm(..set, recovery: segment) })
  }
}

pub fn type_reps(form: Form, index: Int, text: String) -> Form {
  update_set(form, index, fn(set) { SetForm(..set, reps: text) })
}

/// A new set starts as a copy of the last one, which is then changed: sets often differ in one value only.
pub fn add_set(form: Form) -> Form {
  let next = case list.last(form.sets) {
    Ok(last) -> last
    Error(Nil) -> blank_set
  }
  Form(..form, sets: list.append(form.sets, [next]))
}

/// The last set is emptied rather than removed, so its fields stay in the form.
pub fn remove_set(form: Form, index: Int) -> Form {
  let rest =
    form.sets
    |> list.index_map(fn(set, i) { #(set, i) })
    |> list.filter(fn(pair) { pair.1 != index })
    |> list.map(fn(pair) { pair.0 })
  Form(..form, sets: case rest {
    [] -> [blank_set]
    _ -> rest
  })
}

fn update_set(form: Form, index: Int, change: fn(SetForm) -> SetForm) -> Form {
  Form(
    ..form,
    sets: list.index_map(form.sets, fn(set, i) {
      case i == index {
        True -> change(set)
        False -> set
      }
    }),
  )
}

// WORKED OUT FROM THE ZONE (ADR 0106) --------------------------------------------------------------

/// The workout's distance was typed: its duration is worked out from the zone.
pub fn type_distance(form: Form, text: String, zones: PaceZones) -> Form {
  fill(Form(..form, distance_km: text, target_typed: DistanceTyped), zones)
}

pub fn type_duration(form: Form, text: String, zones: PaceZones) -> Form {
  fill(Form(..form, duration: text, target_typed: TimeTyped), zones)
}

/// Another zone works out again whatever was worked out from the one before.
pub fn choose_zone(form: Form, text: String, zones: PaceZones) -> Form {
  fill(Form(..form, zone: text), zones)
}

pub fn choose_kind(form: Form, kind: Kind, zones: PaceZones) -> Form {
  fill(Form(..form, kind: kind), zones)
}

/// Works out the field the user did not type last from the one they did, at the zone's pace in the athlete's
/// pace zones. An interval workout has no zone of its own: each of its parts has one (ADR 0116), and its own
/// distance and duration are left as typed. Nothing changes without a zone, or while the typed value is not
/// usable; clearing the typed value clears the worked-out one.
fn fill(form: Form, zones: PaceZones) -> Form {
  case form.kind {
    plan.Rest | plan.Interval -> form
    _ ->
      case pace_of(form.zone, zones) {
        Ok(pace) -> fill_target(form, pace)
        Error(Nil) -> form
      }
  }
}

fn pace_of(zone: String, zones: PaceZones) -> Result(Int, Nil) {
  case int.parse(string.trim(zone)) {
    Ok(zone) -> pace_zones.planning_pace(zones, zone)
    Error(_) -> Error(Nil)
  }
}

fn fill_target(form: Form, pace: Int) -> Form {
  case form.target_typed {
    NeitherTyped -> form
    DistanceTyped ->
      case string.trim(form.distance_km), target_distance(form.distance_km) {
        "", _ -> Form(..form, duration: "")
        _, Ok(m) if m >. 0.0 ->
          Form(..form, duration: format_duration(minutes_at(m, pace) * 60))
        _, _ -> form
      }
    TimeTyped ->
      case string.trim(form.duration), target_duration(form.duration) {
        "", _ -> Form(..form, distance_km: "")
        _, Ok(s) if s > 0 ->
          Form(..form, distance_km: format_km(hundreds_at(s, pace)))
        _, _ -> form
      }
  }
}

/// To the nearest minute, as durations are typed.
fn minutes_at(metres: Float, pace: Int) -> Int {
  let seconds = float.round(metres *. int.to_float(pace) /. 1000.0)
  int.max({ seconds + 30 } / 60, 1)
}

/// To the nearest 100 m.
fn hundreds_at(seconds: Int, pace: Int) -> Float {
  let m = int.to_float(seconds) *. 1000.0 /. int.to_float(pace)
  int.to_float(int.max(float.round(m /. 100.0), 1) * 100)
}

/// The pace of a part in seconds per kilometre: that of its race goal at its intensity, else that of its zone.
fn segment_pace(
  form: SegmentForm,
  goals: List(RaceGoal),
  zones: PaceZones,
) -> Result(Int, Nil) {
  case string.trim(form.goal) {
    "" -> pace_of(form.zone, zones)
    id ->
      case
        list.find(goals, fn(goal) { goal.id == id }),
        parse_intensity(form.intensity)
      {
        Ok(goal), Ok(intensity) -> goal_pace(goal, intensity)
        _, _ -> Error(Nil)
      }
  }
}

/// A goal's pace at `intensity` percent of its speed (ADR 0118): 10 km in 40:00 is 4:00 /km, and 4:27 /km at 90 %.
pub fn goal_pace(goal: RaceGoal, intensity: Int) -> Result(Int, Nil) {
  case goal.distance_m >. 0.0 && goal.time_s > 0 && intensity > 0 {
    True ->
      Ok(float.round(
        int.to_float(goal.time_s)
        *. 1000.0
        *. 100.0
        /. { goal.distance_m *. int.to_float(intensity) },
      ))
    False -> Error(Nil)
  }
}

/// A whole percentage from 1 to 100.
fn parse_intensity(text: String) -> Result(Int, Nil) {
  case int.parse(string.trim(string.replace(text, "%", ""))) {
    Ok(n) if n >= 1 && n <= 100 -> Ok(n)
    _ -> Error(Nil)
  }
}

/// A warm-up or cool-down to the minute and 100 m, like a workout; a rep or recovery to the second and 10 m.
fn fill_segment(
  form: SegmentForm,
  long: Bool,
  pace: Result(Int, Nil),
) -> SegmentForm {
  case pace, form.typed {
    Error(Nil), _ | _, NeitherTyped -> form
    Ok(pace), DistanceTyped ->
      case string.trim(form.distance), segment_distance(form.distance, long) {
        "", _ -> SegmentForm(..form, time: "")
        _, Ok(m) if m >. 0.0 && long ->
          case minutes_at(m, pace) * 60 {
            s if s <= max_warmup_seconds ->
              SegmentForm(..form, time: format_duration(s))
            _ -> form
          }
        _, Ok(m) if m >. 0.0 ->
          case float.round(m *. int.to_float(pace) /. 1000.0) {
            s if s <= max_rep_seconds ->
              SegmentForm(..form, time: format_rep_time(int.max(s, 1)))
            _ -> form
          }
        _, _ -> form
      }
    Ok(pace), TimeTyped ->
      case string.trim(form.time), segment_time(form.time, long) {
        "", _ -> SegmentForm(..form, distance: "")
        _, Ok(s) if s > 0 && long ->
          SegmentForm(..form, distance: format_km(hundreds_at(s, pace)))
        _, Ok(s) if s > 0 -> {
          let m = int.to_float(s) *. 1000.0 /. int.to_float(pace)
          let tens = int.max(float.round(m /. 10.0), 1)
          SegmentForm(..form, distance: int.to_string(tens * 10))
        }
        _, _ -> form
      }
  }
}

/// All the parts of an interval workout as typed so far (ADR 0106, 0116): the distance in metres and the time in
/// seconds of the parts that have one, with a recovery after every rep but the last of the workout. `None` while no
/// part has one.
pub fn interval_totals(form: Form) -> #(Option(Float), Option(Int)) {
  let reps = fn(set: SetForm) {
    case int.parse(string.trim(set.reps)) {
      Ok(n) if n >= 1 && n <= max_reps -> n
      _ -> 0
    }
  }
  let last_with_reps =
    form.sets
    |> list.index_map(fn(set, i) { #(i, reps(set)) })
    |> list.filter(fn(pair) { pair.1 > 0 })
    |> list.last
    |> result.map(fn(pair) { pair.0 })
    |> result.unwrap(-1)
  // How often each part is run.
  let parts =
    list.flatten([
      [#(form.warmup, True, 1), #(form.cooldown, True, 1)],
      ..list.index_map(form.sets, fn(set, i) {
        let n = reps(set)
        [
          #(set.work, False, n),
          #(set.recovery, False, case i == last_with_reps {
            True -> n - 1
            False -> n
          }),
        ]
      })
    ])
  let distance =
    list.fold(parts, None, fn(total, part) {
      case segment_distance({ part.0 }.distance, part.1) {
        Ok(m) if m >. 0.0 && part.2 > 0 ->
          Some(option.unwrap(total, 0.0) +. int.to_float(part.2) *. m)
        _ -> total
      }
    })
  let time =
    list.fold(parts, None, fn(total, part) {
      case segment_time({ part.0 }.time, part.1) {
        Ok(s) if s > 0 && part.2 > 0 ->
          Some(option.unwrap(total, 0) + part.2 * s)
        _ -> total
      }
    })
  #(distance, time)
}

/// Checks the form; a problem names the field it is about: `week`, `day`, `title`, `description`, `distance`,
/// `duration`, `zone`, or a field of an interval workout's parts (`segment_field_name`, `reps_field_name`).
pub fn validate_fields(form: Form) -> Result(Valid, #(String, String)) {
  let title = string.trim(form.title)
  case
    int.parse(string.trim(form.week)),
    int.parse(string.trim(form.day)),
    string.length(title)
  {
    Error(_), _, _ -> Error(#("week", "Enter the week as a number."))
    Ok(week), _, _ if week < 1 || week > max_weeks ->
      Error(#("week", "The week must be between 1 and 60."))
    _, Error(_), _ -> Error(#("day", "Choose the day of the week."))
    _, Ok(day), _ if day < 1 || day > 7 ->
      Error(#("day", "The day must be between 1 and 7."))
    Ok(week), Ok(day), _ if { week - 1 } * 7 + day - 1 < form.first_day ->
      Error(#("day", "The plan starts after this day."))
    _, _, 0 -> Error(#("title", "Give the workout a title."))
    _, _, n if n > max_title ->
      Error(#("title", "The title can have at most 200 characters."))
    Ok(week), Ok(day), _ -> {
      // An interval workout's distance and duration are those of its parts, not asked for (ADR 0130).
      let checked = case form.kind {
        plan.Interval -> Form(..form, distance_km: "", duration: "")
        _ -> form
      }
      use body <- result.map(validate_body(checked))
      let #(distance_m, duration_s) = case form.kind, body.intervals {
        plan.Interval, Some(parts) -> plan.interval_totals(parts)
        _, _ -> #(body.distance_m, body.duration_s)
      }
      Valid(
        day_index: { week - 1 } * 7 + { day - 1 },
        title: title,
        kind: form.kind,
        distance_m: distance_m,
        duration_s: duration_s,
        description: body.description,
        intervals: body.intervals,
        zone: body.zone,
      )
    }
  }
}

/// What a workout and an activity have in common, checked (ADR 0121): all but the day and the title.
pub type Body {
  Body(
    distance_m: Float,
    duration_s: Int,
    description: String,
    intervals: Option(Intervals),
    zone: Int,
  )
}

/// Checks the fields after the title; a problem names its field as `validate_fields` does.
pub fn validate_body(form: Form) -> Result(Body, #(String, String)) {
  let description = string.trim(form.description)
  case string.length(description) > max_description {
    True ->
      Error(#("description", "The notes can have at most 5000 characters."))
    False ->
      case
        target_distance(form.distance_km),
        target_duration(form.duration),
        intervals(form),
        target_zone(form)
      {
        Error(message), _, _, _ -> Error(#("distance", message))
        _, Error(message), _, _ -> Error(#("duration", message))
        _, _, Error(problem), _ -> Error(problem)
        _, _, _, Error(message) -> Error(#("zone", message))
        Ok(distance), Ok(duration), Ok(intervals), Ok(zone) ->
          Ok(Body(distance, duration, description, intervals, zone))
      }
  }
}

fn target_distance(text: String) -> Result(Float, String) {
  case string.trim(text) {
    "" -> Ok(0.0)
    typed ->
      case parse_decimal(typed) {
        Ok(km) if km <=. max_distance_km -> Ok(km *. 1000.0)
        Ok(_) -> Error("The distance can be at most 1000 km.")
        Error(Nil) ->
          Error("Enter the distance in kilometres, for example 8 or 8.5.")
      }
  }
}

fn target_duration(text: String) -> Result(Int, String) {
  case string.trim(text) {
    "" -> Ok(0)
    typed ->
      case parse_duration(typed) {
        Ok(seconds) if seconds <= max_duration_seconds -> Ok(seconds)
        Ok(_) -> Error("The duration can be at most 48 hours.")
        Error(Nil) ->
          Error(
            "Enter the duration in minutes (45) or as hours and minutes (1:30).",
          )
      }
  }
}

/// The target zone; a rest day has none, whatever was chosen before its kind was changed (ADR 0105), and an
/// interval workout has none of its own: each of its parts has one (ADR 0117).
fn target_zone(form: Form) -> Result(Int, String) {
  case form.kind, int.parse(string.trim(form.zone)) {
    plan.Rest, _ | plan.Interval, _ -> Ok(0)
    _, _ if form.zone == "" -> Ok(0)
    _, Ok(n) if n >= 1 && n <= 5 -> Ok(n)
    _, _ -> Error("Choose a zone from 1 to 5.")
  }
}

/// `Zone 2`, `""` for none.
pub fn zone_label(zone: Int) -> String {
  case zone {
    0 -> ""
    n -> "Zone " <> int.to_string(n)
  }
}

/// The parts, for an interval workout, and the warm-up and cool-down of a race (ADR 0119): none when every field
/// of them is empty, as before they existed (ADR 0104). Sets left empty are left out.
fn intervals(form: Form) -> Result(Option(Intervals), #(String, String)) {
  case form.kind {
    plan.Interval | plan.Race -> {
      use warmup <- result.try(valid_segment(form.warmup, Warmup, form.goals))
      use sets <- result.try(case form.kind {
        plan.Interval ->
          form.sets
          |> list.index_map(fn(set, i) { #(set, i) })
          |> list.filter(fn(pair) { !is_blank_set(pair.0) })
          |> list.try_map(fn(pair) { valid_set(pair.0, pair.1, form.goals) })
        _ -> Ok([])
      })
      use cooldown <- result.try(valid_segment(
        form.cooldown,
        Cooldown,
        form.goals,
      ))
      case warmup == plan.no_segment, sets, cooldown == plan.no_segment {
        True, [], True -> Ok(None)
        _, _, _ -> Ok(Some(Intervals(warmup, sets, cooldown)))
      }
    }
    _ -> Ok(None)
  }
}

fn is_blank_set(set: SetForm) -> Bool {
  [set.reps, ..list.flat_map([set.work, set.recovery], segment_texts)]
  |> list.all(fn(text) { string.trim(text) == "" })
}

fn segment_texts(segment: SegmentForm) -> List(String) {
  [segment.zone, segment.distance, segment.time, segment.goal]
}

fn valid_set(
  set: SetForm,
  index: Int,
  goals: List(RaceGoal),
) -> Result(plan.Set, #(String, String)) {
  let reps = string.trim(set.reps)
  let field = reps_field_name(index)
  case int.parse(reps) {
    Error(_) if reps == "" -> Error(#(field, "Enter how many repetitions."))
    Error(_) -> Error(#(field, "Enter the repetitions as a whole number."))
    Ok(n) if n < 1 || n > max_reps ->
      Error(#(field, "The repetitions must be between 1 and 100."))
    Ok(n) -> {
      use work <- result.try(valid_segment(set.work, Work(index), goals))
      use recovery <- result.try(valid_segment(
        set.recovery,
        Recovery(index),
        goals,
      ))
      case work {
        plan.Segment(_, 0.0, 0, _) ->
          Error(#(
            segment_field_name(Work(index), DistanceField),
            "Give each rep a distance, a time or both.",
          ))
        _ -> Ok(plan.Set(n, work, recovery))
      }
    }
  }
}

/// An empty part is `plan.no_segment`; a part with a zone needs a distance or a time.
fn valid_segment(
  form: SegmentForm,
  part: Part,
  goals: List(RaceGoal),
) -> Result(Segment, #(String, String)) {
  let long = is_long(part)
  let zone = case string.trim(form.zone), int.parse(string.trim(form.zone)) {
    "", _ -> Ok(0)
    _, Ok(n) if n >= 1 && n <= 5 -> Ok(n)
    _, _ -> Error("Choose a zone from 1 to 5.")
  }
  use goal <- result.try(valid_goal(form, part, goals))
  case
    zone,
    segment_distance(form.distance, long)
    |> result.map_error(fn(message) { distance_message(message, part) }),
    segment_time(form.time, long)
    |> result.map_error(fn(message) { time_message(message, part) })
  {
    Error(message), _, _ ->
      Error(#(segment_field_name(part, ZoneField), message))
    _, Error(message), _ ->
      Error(#(segment_field_name(part, DistanceField), message))
    _, _, Error(message) ->
      Error(#(segment_field_name(part, TimeField), message))
    Ok(zone), Ok(0.0), Ok(0) if zone > 0 ->
      case part {
        // A rep without a length is reported as such by `valid_set`.
        Work(_) -> Ok(plan.Segment(zone, 0.0, 0, goal))
        _ ->
          Error(#(
            segment_field_name(part, DistanceField),
            "Give the " <> part_name(part) <> " a distance, a time or both.",
          ))
      }
    Ok(zone), Ok(distance), Ok(time) ->
      Ok(plan.Segment(zone, distance, time, goal))
  }
}

/// A part's race goal and intensity (ADR 0118), with the goal's distance and time as they are now.
fn valid_goal(
  form: SegmentForm,
  part: Part,
  goals: List(RaceGoal),
) -> Result(Option(GoalPace), #(String, String)) {
  case string.trim(form.goal) {
    "" -> Ok(None)
    id ->
      case
        list.find(goals, fn(goal) { goal.id == id }),
        parse_intensity(form.intensity)
      {
        Error(Nil), _ ->
          Error(#(segment_field_name(part, GoalField), "Choose a race goal."))
        _, Error(Nil) ->
          Error(#(
            segment_field_name(part, IntensityField),
            "Enter the intensity as a whole number from 1 to 100.",
          ))
        Ok(goal), Ok(intensity) ->
          Ok(Some(GoalPace(goal.id, goal.distance_m, goal.time_s, intensity)))
      }
  }
}

/// What went wrong with a distance: too long, or not a number.
type Problem {
  TooLong
  NotUnderstood
}

fn segment_distance(text: String, long: Bool) -> Result(Float, Problem) {
  case string.trim(text), long {
    "", _ -> Ok(0.0)
    typed, True ->
      case parse_decimal(typed) {
        Ok(km) if km *. 1000.0 <=. max_warmup_distance_m ->
          Ok(int.to_float(float.round(km *. 1000.0)))
        Ok(_) -> Error(TooLong)
        Error(Nil) -> Error(NotUnderstood)
      }
    typed, False ->
      case parse_decimal(typed) {
        Ok(m) if m <=. max_rep_distance_m -> Ok(int.to_float(float.round(m)))
        Ok(_) -> Error(TooLong)
        Error(Nil) -> Error(NotUnderstood)
      }
  }
}

fn segment_time(text: String, long: Bool) -> Result(Int, Problem) {
  case string.trim(text), long {
    "", _ -> Ok(0)
    typed, True ->
      case parse_duration(typed) {
        Ok(seconds) if seconds <= max_warmup_seconds -> Ok(seconds)
        Ok(_) -> Error(TooLong)
        Error(Nil) -> Error(NotUnderstood)
      }
    typed, False ->
      case parse_rep_time(typed) {
        Ok(seconds) if seconds <= max_rep_seconds -> Ok(seconds)
        Ok(_) -> Error(TooLong)
        Error(Nil) -> Error(NotUnderstood)
      }
  }
}

fn distance_message(problem: Problem, part: Part) -> String {
  case problem, is_long(part) {
    TooLong, True -> "The " <> part_name(part) <> " can be at most 50 km."
    NotUnderstood, True ->
      "Enter the distance in kilometres, for example 2 or 2.5."
    TooLong, False ->
      "The distance of a " <> part_name(part) <> " can be at most 20000 m."
    NotUnderstood, False -> "Enter the distance in metres, for example 400."
  }
}

fn time_message(problem: Problem, part: Part) -> String {
  case problem, is_long(part) {
    TooLong, True -> "The " <> part_name(part) <> " can be at most 5 hours."
    NotUnderstood, True ->
      "Enter the time in minutes (15) or as hours and minutes (1:30)."
    TooLong, False ->
      "The time of a " <> part_name(part) <> " can be at most 60 minutes."
    NotUnderstood, False ->
      "Enter the time in seconds (90) or as minutes and seconds (1:30)."
  }
}

fn part_name(part: Part) -> String {
  case part {
    Warmup -> "warm-up"
    Cooldown -> "cool-down"
    Work(_) -> "rep"
    Recovery(_) -> "recovery"
  }
}

/// The name a problem gives a field of a part: `warmup_time`, `set2_work_distance`, `set1_recovery_zone`.
pub fn segment_field_name(part: Part, field: SegmentField) -> String {
  let prefix = case part {
    Warmup -> "warmup"
    Cooldown -> "cooldown"
    Work(index) -> "set" <> int.to_string(index + 1) <> "_work"
    Recovery(index) -> "set" <> int.to_string(index + 1) <> "_recovery"
  }
  prefix
  <> case field {
    ZoneField -> "_zone"
    DistanceField -> "_distance"
    TimeField -> "_time"
    GoalField -> "_goal"
    IntensityField -> "_intensity"
    TargetField -> "_target"
  }
}

/// `set1_reps`.
pub fn reps_field_name(index: Int) -> String {
  "set" <> int.to_string(index + 1) <> "_reps"
}

/// Seconds from `90` (seconds), `1:30` (minutes and seconds) or `1:00:00` (with hours): reps and
/// recoveries are short, so a plain number means seconds here, not minutes as in `parse_duration`.
pub fn parse_rep_time(text: String) -> Result(Int, Nil) {
  case list.try_map(string.split(string.trim(text), ":"), parse_part) {
    Ok([seconds]) -> Ok(seconds)
    Ok([minutes, seconds]) if seconds < 60 -> Ok(minutes * 60 + seconds)
    Ok([hours, minutes, seconds]) if minutes < 60 && seconds < 60 ->
      Ok(hours * 3600 + minutes * 60 + seconds)
    _ -> Error(Nil)
  }
}

/// A rep or recovery time as it is typed back into the form and shown: `0:45`, `3:00`, `1:00:00`.
pub fn format_rep_time(seconds: Int) -> String {
  case seconds >= 3600 {
    True -> format_duration(seconds)
    False -> int.to_string(seconds / 60) <> ":" <> pad2(seconds % 60)
  }
}

/// `15:00 warm-up (Zone 1)`, `""` without one: the warm-up of an interval workout or a race (ADR 0116, 0119).
pub fn warmup_summary(intervals: Intervals) -> String {
  segment_summary(intervals.warmup, "warm-up")
}

pub fn cooldown_summary(intervals: Intervals) -> String {
  segment_summary(intervals.cooldown, "cool-down")
}

/// `2 km warm-up (Zone 1) · 6 × 800 m in 2:50 (Zone 4), 1:30 recovery · 1 km cool-down`: the warm-up, each set
/// and the cool-down (ADR 0116).
pub fn intervals_summary(intervals: Intervals) -> String {
  let sets =
    list.map(intervals.sets, fn(set) {
      let recovery = case set.recovery {
        plan.Segment(_, 0.0, 0, _) -> ""
        recovery -> ", " <> segment_summary(recovery, "recovery")
      }
      int.to_string(set.reps)
      <> " × "
      <> segment_summary(set.work, "")
      <> recovery
    })
  [
    segment_summary(intervals.warmup, "warm-up"),
    ..list.append(sets, [segment_summary(intervals.cooldown, "cool-down")])
  ]
  |> list.filter(fn(part) { part != "" })
  |> string.join(" · ")
}

/// `800 m in 2:50 (Zone 4)`, `400 m in 1:12 (95 % of 10 km pace)`, `15:00 warm-up`; `""` for a part without a
/// distance or time.
fn segment_summary(segment: Segment, name: String) -> String {
  let distance = case segment.distance_m {
    m if m >=. 1000.0 -> format_km(m) <> " km"
    m if m >. 0.0 -> int.to_string(float.round(m)) <> " m"
    _ -> ""
  }
  let length = case distance, segment.duration_s {
    "", 0 -> ""
    "", s -> format_rep_time(s)
    _, 0 -> distance
    _, s -> distance <> " in " <> format_rep_time(s)
  }
  let target = case segment.goal, segment.zone {
    Some(goal), _ -> goal_pace_label(goal)
    None, zone -> zone_label(zone)
  }
  case length, name, target {
    "", _, _ -> ""
    _, "", "" -> length
    _, _, "" -> length <> " " <> name
    _, "", target -> length <> " (" <> target <> ")"
    _, _, target -> length <> " " <> name <> " (" <> target <> ")"
  }
}

/// `10 km pace`, `95 % of 10 km pace`
pub fn goal_pace_label(goal: GoalPace) -> String {
  let pace = format_km(goal.distance_m) <> " km pace"
  case goal.intensity {
    100 -> pace
    n -> int.to_string(n) <> " % of " <> pace
  }
}

/// A non-negative decimal number, with a point or a comma: `5`, `5.5`, `5,5`, `.5`.
pub fn parse_decimal(text: String) -> Result(Float, Nil) {
  let normal = string.replace(string.trim(text), ",", ".")
  let candidate = case string.starts_with(normal, ".") {
    True -> "0" <> normal
    False -> normal
  }
  case int.parse(candidate) {
    Ok(whole) if whole >= 0 -> Ok(int.to_float(whole))
    Ok(_) -> Error(Nil)
    Error(_) ->
      case string.ends_with(candidate, "."), float.parse(candidate) {
        True, _ -> parse_decimal(string.drop_end(candidate, 1))
        False, Ok(value) if value >=. 0.0 -> Ok(value)
        _, _ -> Error(Nil)
      }
  }
}

/// Seconds from `45` (minutes), `1:30` (hours and minutes) or `1:30:15` (with seconds).
pub fn parse_duration(text: String) -> Result(Int, Nil) {
  case list.try_map(string.split(string.trim(text), ":"), parse_part) {
    Ok([minutes]) -> Ok(minutes * 60)
    Ok([hours, minutes]) if minutes < 60 -> Ok(hours * 3600 + minutes * 60)
    Ok([hours, minutes, seconds]) if minutes < 60 && seconds < 60 ->
      Ok(hours * 3600 + minutes * 60 + seconds)
    _ -> Error(Nil)
  }
}

fn parse_part(part: String) -> Result(Int, Nil) {
  case int.parse(string.trim(part)) {
    Ok(n) if n >= 0 -> Ok(n)
    _ -> Error(Nil)
  }
}

/// A distance as it is typed back into the form: `8`, `8.5`, `10.234`.
pub fn format_km(meters: Float) -> String {
  let thousandths = float.round(meters)
  let whole = thousandths / 1000
  let rest = thousandths % 1000
  case rest {
    0 -> int.to_string(whole)
    _ -> {
      let digits =
        string.pad_start(int.to_string(rest), 3, "0")
        |> trim_trailing_zeros
      int.to_string(whole) <> "." <> digits
    }
  }
}

fn trim_trailing_zeros(text: String) -> String {
  case string.ends_with(text, "0") {
    True -> trim_trailing_zeros(string.drop_end(text, 1))
    False -> text
  }
}

/// A duration as it is typed back into the form: `45`, `1:30` or `1:30:15`.
pub fn format_duration(seconds: Int) -> String {
  let hours = seconds / 3600
  let minutes = { seconds % 3600 } / 60
  let rest = seconds % 60
  case hours, rest {
    0, 0 -> int.to_string(minutes)
    _, 0 -> int.to_string(hours) <> ":" <> pad2(minutes)
    _, _ -> int.to_string(hours) <> ":" <> pad2(minutes) <> ":" <> pad2(rest)
  }
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}

// FIELDS TO WRITE ---------------------------------------------------------------------------------

/// The fields of a new workout. `position` orders it among the workouts of its day.
pub fn create_fields(
  plan_id: String,
  position: Int,
  valid: Valid,
) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("plan", plan_id),
    outbox.field_int("position", position),
    ..value_fields(valid)
  ])
}

/// Only what differs from the stored workout. When the day changes the workout moves to the end
/// of its new day (`new_position`). Empty when nothing changed.
pub fn changed_fields(
  row: Row,
  valid: Valid,
  new_position: Int,
) -> outbox.Fields {
  let w = row.workout
  let moved = valid.day_index != w.day_index
  let changed =
    value_fields(valid)
    |> list.filter(fn(field) {
      case field.0 {
        "day_index" -> moved
        "title" -> valid.title != w.title
        "kind" -> valid.kind != w.kind
        "description" -> valid.description != row.description
        "distance_m" -> valid.distance_m != option.unwrap(w.distance_m, 0.0)
        "duration_s" -> valid.duration_s != option.unwrap(w.duration_s, 0)
        // Steps of the first version take their reps' zone from the workout's (ADR 0116): when that goes, they are
        // written again with the zone in the reps (ADR 0117).
        "steps" ->
          valid.intervals != row.intervals
          || {
            valid.zone != row.zone
            && valid.kind == plan.Interval
            && option.is_some(valid.intervals)
          }
        "zone" -> valid.zone != row.zone
        _ -> False
      }
    })
  let with_position = case moved {
    True -> [outbox.field_int("position", new_position), ..changed]
    False -> changed
  }
  dict.from_list(with_position)
}

fn value_fields(valid: Valid) -> List(#(String, String)) {
  [
    outbox.field_int("day_index", valid.day_index),
    outbox.field_string("title", valid.title),
    outbox.field_string("kind", plan.kind_to_string(valid.kind)),
    outbox.field_string("description", valid.description),
    outbox.field_float("distance_m", valid.distance_m),
    outbox.field_int("duration_s", valid.duration_s),
    steps_field(valid.intervals),
    outbox.field_int("zone", valid.zone),
  ]
}

/// The parts as the `steps` JSON (ADR 0104, 0116), `null` when there are none. Unset values and parts are left out.
pub fn steps_field(intervals: Option(Intervals)) -> #(String, String) {
  case intervals {
    None -> outbox.field_null("steps")
    Some(i) -> {
      let set_json = fn(set: plan.Set) {
        json.object([
          #("reps", json.int(set.reps)),
          #("work", segment_json(set.work)),
          ..optional_segment("recovery", set.recovery)
        ])
      }
      #(
        "steps",
        json.object(
          list.flatten([
            [#("v", json.int(2))],
            optional_segment("warmup", i.warmup),
            case i.sets {
              [] -> []
              sets -> [#("sets", json.array(sets, set_json))]
            },
            optional_segment("cooldown", i.cooldown),
          ]),
        )
          |> json.to_string,
      )
    }
  }
}

fn optional_segment(
  name: String,
  segment: Segment,
) -> List(#(String, json.Json)) {
  case segment == plan.no_segment {
    True -> []
    False -> [#(name, segment_json(segment))]
  }
}

fn segment_json(segment: Segment) -> json.Json {
  [
    #("zone", segment.zone > 0, json.int(segment.zone)),
    #("distance_m", segment.distance_m >. 0.0, json.float(segment.distance_m)),
    #("duration_s", segment.duration_s > 0, json.int(segment.duration_s)),
    ..case segment.goal {
      Some(goal) -> [
        #(
          "goal",
          True,
          json.object([
            #("id", json.string(goal.goal_id)),
            #("distance_m", json.float(goal.distance_m)),
            #("time_s", json.int(goal.time_s)),
            #("intensity", json.int(goal.intensity)),
          ]),
        ),
      ]
      None -> []
    }
  ]
  |> list.filter(fn(part) { part.1 })
  |> list.map(fn(part) { #(part.0, part.2) })
  |> json.object
}

pub fn kind_label(kind: Kind) -> String {
  case kind {
    plan.Run -> "Run"
    plan.Interval -> "Intervals"
    plan.Race -> "Race"
    plan.Rest -> "Rest day"
  }
}

/// The form's problem without the field it is about (ADR 0059).
pub fn validate(form: Form) -> Result(Valid, String) {
  validate_fields(form) |> result.map_error(fn(problem) { problem.1 })
}

/// The field the form's problem is about, `""` when there is none: its error is shown under that field (ADR 0059).
pub fn error_field(form: Form) -> String {
  case validate_fields(form) {
    Error(#(field, _)) -> field
    Ok(_) -> ""
  }
}
