//// Reads synced records (the JSON objects PocketBase sends, kept as they are in IndexedDB) into the
//// domain types. A record that cannot be read is skipped, never a crash: a newer server may have
//// added values this client does not know yet.

import atlas/activity.{type Activity, Activity}
import atlas/activity_form
import atlas/assignment_form
import atlas/athlete_settings
import atlas/date
import atlas/goal.{type Goal, Goal}
import atlas/grants.{type Grant, Grant}
import atlas/hr_zones
import atlas/lactate_zones
import atlas/matching.{type Stored, Match, Stored}
import atlas/pace_zones
import atlas/plan.{
  type Assignment, type Plan, type Workout, Assignment, Plan, Workout,
}
import atlas/workout_form.{type Row, Row}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}

pub fn plan(record: Dynamic) -> Result(Plan, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use owner <- decode.optional_field("owner", "", decode.string)
    use title <- decode.field("title", decode.string)
    use description <- decode.optional_field("description", "", decode.string)
    use updated <- decode.optional_field("updated", "", decode.string)
    use base_weeks <- decode.optional_field("base_weeks", 0, whole_number())
    use pre_weeks <- decode.optional_field(
      "pre_competition_weeks",
      0,
      whole_number(),
    )
    use competition_weeks <- decode.optional_field(
      "competition_weeks",
      0,
      whole_number(),
    )
    use goal <- decode.optional_field("weekly_distance_m", 0.0, number())
    use intensities <- decode.optional_field(
      "week_intensity",
      dict.new(),
      week_intensity_decoder(),
    )
    // Plans made before ADR 0108 have none; a date that cannot be read counts as none too.
    use start <- decode.optional_field(
      "start_date",
      None,
      decode.one_of(decode.map(date_decoder(), Some), [decode.success(None)]),
    )
    decode.success(Plan(
      id: id,
      owner_id: owner,
      title: title,
      description: description,
      updated: updated,
      phases: plan.Phases(base_weeks, pre_weeks, competition_weeks),
      weekly_distance_m: case goal >. 0.0 {
        True -> Some(goal)
        False -> None
      },
      week_intensity: intensities,
      start_date: start,
    ))
  })
}

/// One intensity (0.0 to 1.0) per week, in week order (`[null, 0.8]`: week 2 is at 80%), or `null` when nothing
/// was set. `null` or anything that is not a number means "not set", so one odd value does not hide the plan;
/// numbers out of range are clamped. A list, not an object keyed by week, because objects from IndexedDB need
/// not come from the app's own JavaScript realm.
fn week_intensity_decoder() -> Decoder(Dict(Int, Float)) {
  decode.one_of(
    decode.list(
      decode.one_of(decode.map(number(), Ok), [decode.success(Error(Nil))]),
    )
      |> decode.map(fn(levels) {
        list.index_fold(levels, dict.new(), fn(acc, level, index) {
          case level {
            Ok(value) -> dict.insert(acc, index + 1, plan.intensity(value))
            Error(Nil) -> acc
          }
        })
      }),
    [decode.success(dict.new())],
  )
}

/// A target of 0 (what PocketBase stores for "none") becomes `None`.
pub fn workout(record: Dynamic) -> Result(Workout, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use plan_id <- decode.field("plan", decode.string)
    use day_index <- decode.optional_field("day_index", 0, whole_number())
    use position <- decode.optional_field("position", 0, whole_number())
    use title <- decode.field("title", decode.string)
    use kind <- decode.field("kind", kind_decoder())
    use distance <- decode.optional_field("distance_m", 0.0, number())
    use duration <- decode.optional_field("duration_s", 0, whole_number())
    decode.success(
      Workout(
        id: id,
        plan_id: plan_id,
        day_index: day_index,
        position: position,
        title: title,
        kind: kind,
        distance_m: case distance >. 0.0 {
          True -> Some(distance)
          False -> None
        },
        duration_s: case duration > 0 {
          True -> Some(duration)
          False -> None
        },
      ),
    )
  })
}

/// A workout with the fields only the editing screen needs.
pub fn workout_row(record: Dynamic) -> Result(Row, Nil) {
  case workout(record) {
    Error(Nil) -> Error(Nil)
    Ok(found) ->
      run(record, {
        use description <- decode.optional_field(
          "description",
          "",
          decode.string,
        )
        use steps <- decode.optional_field(
          "steps",
          Error(Nil),
          decode.one_of(decode.map(steps_decoder(), Ok), [
            decode.success(Error(Nil)),
          ]),
        )
        // Not required: workouts saved before it existed have none (ADR 0105).
        use zone <- decode.optional_field(
          "zone",
          0,
          decode.one_of(whole_number(), [decode.success(0)]),
        )
        use updated <- decode.optional_field("updated", "", decode.string)
        let zone = zone_or_none(zone)
        let intervals = case steps {
          Ok(read) -> Some(read(zone))
          Error(Nil) -> None
        }
        decode.success(Row(found, description, intervals, zone, updated))
      })
  }
}

/// The parts of an interval workout in its `steps` (ADR 0104, 0116), given the workout's zone: the first version
/// had one set and the workout's zone was that of its reps. Steps this client cannot read, such as a later
/// version, are ignored rather than making the workout unreadable.
fn steps_decoder() -> Decoder(fn(Int) -> plan.Intervals) {
  use version <- decode.field("v", whole_number())
  case version {
    1 -> {
      use set <- decode.then(set_decoder())
      decode.success(fn(zone) {
        plan.Intervals(
          plan.no_segment,
          [plan.Set(..set, work: plan.Segment(..set.work, zone: zone))],
          plan.no_segment,
        )
      })
    }
    2 -> {
      use warmup <- decode.optional_field(
        "warmup",
        plan.no_segment,
        segment_decoder(),
      )
      use sets <- decode.optional_field("sets", [], decode.list(set_decoder()))
      use cooldown <- decode.optional_field(
        "cooldown",
        plan.no_segment,
        segment_decoder(),
      )
      let found = plan.Intervals(warmup, sets, cooldown)
      case
        sets == [] && warmup == plan.no_segment && cooldown == plan.no_segment
      {
        True -> decode.failure(fn(_) { found }, "Intervals")
        False -> decode.success(fn(_) { found })
      }
    }
    _ ->
      decode.failure(
        fn(_) { plan.Intervals(plan.no_segment, [], plan.no_segment) },
        "Intervals",
      )
  }
}

fn set_decoder() -> Decoder(plan.Set) {
  use reps <- decode.field("reps", whole_number())
  use work <- decode.field("work", segment_decoder())
  use recovery <- decode.optional_field(
    "recovery",
    plan.no_segment,
    segment_decoder(),
  )
  let found = plan.Set(reps, work, recovery)
  case reps > 0 && { work.distance_m >. 0.0 || work.duration_s > 0 } {
    True -> decode.success(found)
    False -> decode.failure(found, "Set")
  }
}

fn segment_decoder() -> Decoder(plan.Segment) {
  use zone <- decode.optional_field(
    "zone",
    0,
    decode.one_of(whole_number(), [decode.success(0)]),
  )
  use distance <- decode.optional_field("distance_m", 0.0, number())
  use time <- decode.optional_field("duration_s", 0, whole_number())
  decode.success(plan.Segment(zone_or_none(zone), distance, time))
}

/// A zone from 1 to 5, 0 for none or one this client does not know (ADR 0105).
fn zone_or_none(zone: Int) -> Int {
  case zone >= 1 && zone <= 5 {
    True -> zone
    False -> 0
  }
}

pub fn assignment(record: Dynamic) -> Result(Assignment, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use plan_id <- decode.field("plan", decode.string)
    use athlete <- decode.field("athlete", decode.string)
    // Empty: the assignment follows its plan's start date (ADR 0108).
    use start <- decode.optional_field(
      "start_date",
      None,
      decode.one_of(decode.map(date_decoder(), Some), [
        decode.string
        |> decode.then(fn(text) {
          case text {
            "" -> decode.success(None)
            _ -> decode.failure(None, "Date")
          }
        }),
      ]),
    )
    decode.success(Assignment(id, plan_id, athlete, start))
  })
}

/// An activity with the fields only the screens need.
pub fn activity_row(record: Dynamic) -> Result(activity_form.Row, Nil) {
  case activity(record) {
    Error(Nil) -> Error(Nil)
    Ok(found) ->
      run(record, {
        use owner <- decode.optional_field("owner", "", decode.string)
        use name <- decode.optional_field("name", "", decode.string)
        use elevation <- decode.optional_field(
          "elevation_gain_m",
          0.0,
          number(),
        )
        use heart_rate <- decode.optional_field("avg_hr", 0, whole_number())
        use updated <- decode.optional_field("updated", "", decode.string)
        use external_id <- decode.optional_field(
          "external_id",
          "",
          decode.string,
        )
        decode.success(activity_form.Row(
          found,
          owner,
          name,
          elevation,
          heart_rate,
          updated,
          external_id,
        ))
      })
  }
}

/// An assignment with the fields only the screens need.
pub fn assignment_row(record: Dynamic) -> Result(assignment_form.Row, Nil) {
  case assignment(record) {
    Error(Nil) -> Error(Nil)
    Ok(found) ->
      run(record, {
        use assigned_by <- decode.optional_field(
          "assigned_by",
          "",
          decode.string,
        )
        use updated <- decode.optional_field("updated", "", decode.string)
        decode.success(assignment_form.Row(found, assigned_by, updated))
      })
  }
}

/// A stored match, removed ones included (they matter: the row is reused to link the activity again).
pub fn stored_match(record: Dynamic) -> Result(Stored, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use activity_id <- decode.field("activity", decode.string)
    use assignment_id <- decode.field("assignment", decode.string)
    use workout_id <- decode.field("workout", decode.string)
    use owner <- decode.optional_field("owner", "", decode.string)
    use deleted <- decode.optional_field("deleted", False, decode.bool)
    use updated <- decode.optional_field("updated", "", decode.string)
    decode.success(Stored(
      id,
      owner,
      Match(activity_id, workout_id, assignment_id),
      deleted,
      updated,
    ))
  })
}

/// A race goal (ADR 0115). One without a distance or a time is skipped.
pub fn goal(record: Dynamic) -> Result(Goal, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use owner <- decode.field("owner", decode.string)
    use distance_m <- decode.field("distance_m", number())
    use time_s <- decode.field("time_s", whole_number())
    use updated <- decode.optional_field("updated", "", decode.string)
    case distance_m >. 0.0 && time_s > 0 {
      True -> decode.success(Goal(id, owner, distance_m, time_s, updated))
      False -> decode.failure(Goal(id, owner, 0.0, 0, updated), "Goal")
    }
  })
}

pub fn grant(record: Dynamic) -> Result(Grant, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use athlete <- decode.field("athlete", decode.string)
    use coach <- decode.field("coach", decode.string)
    use athlete_name <- decode.optional_field("athlete_name", "", decode.string)
    use coach_name <- decode.optional_field("coach_name", "", decode.string)
    use updated <- decode.optional_field("updated", "", decode.string)
    decode.success(Grant(id, athlete, coach, athlete_name, coach_name, updated))
  })
}

/// An athlete's zones. Heart-rate zones with a value missing or out of order make the row unusable, so it is
/// skipped and the defaults apply instead of half-saved zones. Lactate and pace zones that are missing or unusable
/// (rows saved before they existed hold zeros) fall back to their own defaults alone.
pub fn athlete_settings_row(
  record: Dynamic,
) -> Result(athlete_settings.Row, Nil) {
  let read = {
    use owner <- decode.field("owner", decode.string)
    use max_hr <- decode.field("max_hr", whole_number())
    use z1 <- decode.field(hr_zones.start_field(1), whole_number())
    use z2 <- decode.field(hr_zones.start_field(2), whole_number())
    use z3 <- decode.field(hr_zones.start_field(3), whole_number())
    use z4 <- decode.field(hr_zones.start_field(4), whole_number())
    use z5 <- decode.field(hr_zones.start_field(5), whole_number())
    use l1 <- lactate_start(1)
    use l2 <- lactate_start(2)
    use l3 <- lactate_start(3)
    use l4 <- lactate_start(4)
    use l5 <- lactate_start(5)
    use threshold <- optional_whole(pace_zones.threshold_field)
    use p1 <- optional_whole(pace_zones.start_field(1))
    use p2 <- optional_whole(pace_zones.start_field(2))
    use p3 <- optional_whole(pace_zones.start_field(3))
    use p4 <- optional_whole(pace_zones.start_field(4))
    use p5 <- optional_whole(pace_zones.start_field(5))
    use updated <- decode.optional_field("updated", "", decode.string)
    decode.success(#(
      owner,
      hr_zones.HrZones(max_hr, [z1, z2, z3, z4, z5]),
      [l1, l2, l3, l4, l5],
      pace_zones.PaceZones(threshold, [p1, p2, p3, p4, p5]),
      updated,
    ))
  }
  case run(record, read) {
    Error(Nil) -> Error(Nil)
    Ok(#(owner, hr, lactate, pace, updated)) ->
      case hr_zones.parse(hr_zones.to_form(hr)) {
        Error(_) -> Error(Nil)
        Ok(hr) -> {
          let lactate = case
            lactate_zones.parse(list.map(lactate, lactate_zones.format))
          {
            Ok(zones) -> zones
            Error(_) -> lactate_zones.defaults()
          }
          let pace = case pace_zones.parse(pace_zones.to_form(pace)) {
            Ok(zones) -> zones
            Error(_) -> pace_zones.defaults(pace_zones.default_threshold_s)
          }
          Ok(athlete_settings.Row(owner, hr, lactate, pace, updated))
        }
      }
  }
}

/// Where a lactate zone starts, in tenths; 0 when missing.
fn lactate_start(zone: Int, next: fn(Int) -> Decoder(a)) -> Decoder(a) {
  use mmol <- decode.optional_field(
    lactate_zones.start_field(zone),
    0.0,
    number(),
  )
  next(lactate_zones.tenths_of(mmol))
}

/// A whole number that may be missing (0 then).
fn optional_whole(name: String, next: fn(Int) -> Decoder(a)) -> Decoder(a) {
  use value <- decode.optional_field(name, 0, whole_number())
  next(value)
}

pub fn activity(record: Dynamic) -> Result(Activity, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use source <- decode.field("source", source_decoder())
    use started_at <- decode.field("started_at", decode.string)
    use sport <- decode.field("sport", sport_decoder())
    use distance <- decode.optional_field("distance_m", 0.0, number())
    use moving <- decode.optional_field("moving_time_s", 0, whole_number())
    decode.success(Activity(id, source, started_at, sport, distance, moving))
  })
}

/// The readable, not soft-deleted records of a list, in their original order.
pub fn live(
  records: List(Dynamic),
  read: fn(Dynamic) -> Result(a, Nil),
) -> List(a) {
  records
  |> list.filter(fn(record) { !is_deleted(record) })
  |> list.filter_map(read)
}

pub fn is_deleted(record: Dynamic) -> Bool {
  case
    decode.run(
      record,
      decode.optional_field("deleted", False, decode.bool, decode.success),
    )
  {
    Ok(deleted) -> deleted
    Error(_) -> False
  }
}

// DECODERS ----------------------------------------------------------------------------------------

fn run(record: Dynamic, decoder: Decoder(a)) -> Result(a, Nil) {
  case decode.run(record, decoder) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}

/// A JSON number as a float. JavaScript has one number type, and PocketBase writes `10000`, not
/// `10000.0`, so the plain float decoder would refuse whole numbers.
fn number() -> Decoder(Float) {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

/// A whole number, also when it arrives as `3.0`.
fn whole_number() -> Decoder(Int) {
  decode.one_of(decode.int, [decode.map(decode.float, float.truncate)])
}

fn kind_decoder() -> Decoder(plan.Kind) {
  use text <- decode.then(decode.string)
  case plan.kind_from_string(text) {
    Ok(kind) -> decode.success(kind)
    Error(Nil) -> decode.failure(plan.Run, "Kind")
  }
}

fn source_decoder() -> Decoder(activity.Source) {
  use text <- decode.then(decode.string)
  case activity.source_from_string(text) {
    Ok(source) -> decode.success(source)
    Error(Nil) -> decode.failure(activity.Manual, "Source")
  }
}

fn sport_decoder() -> Decoder(activity.Sport) {
  use text <- decode.then(decode.string)
  case activity.sport_from_string(text) {
    Ok(sport) -> decode.success(sport)
    Error(Nil) -> decode.failure(activity.Other, "Sport")
  }
}

fn date_decoder() -> Decoder(date.Date) {
  use text <- decode.then(decode.string)
  case date.parse(text) {
    Ok(day) -> decode.success(day)
    Error(Nil) -> decode.failure(date.Date(1970, 1, 1), "Date")
  }
}
