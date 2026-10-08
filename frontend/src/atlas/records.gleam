//// Reads synced records (the JSON objects PocketBase sends, kept as they are in IndexedDB) into the
//// domain types. A record that cannot be read is skipped, never a crash: a newer server may have
//// added values this client does not know yet.

import atlas/activity.{type Activity, Activity}
import atlas/activity_form
import atlas/assignment_form
import atlas/athlete_settings
import atlas/date
import atlas/grants.{type Grant, Grant}
import atlas/hr_zones
import atlas/lactate_zones
import atlas/matching.{type Stored, Match, Stored}
import atlas/pace_zones
import atlas/plan.{
  type Assignment, type Plan, type Workout, Assignment, Plan, Workout,
}
import atlas/shares.{type Share, Share}
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
    use visibility <- decode.optional_field(
      "visibility",
      "private",
      decode.string,
    )
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
    decode.success(Plan(
      id: id,
      owner_id: owner,
      title: title,
      description: description,
      visibility: case visibility {
        "public" -> plan.Public
        _ -> plan.Private
      },
      updated: updated,
      phases: plan.Phases(base_weeks, pre_weeks, competition_weeks),
      weekly_distance_m: case goal >. 0.0 {
        True -> Some(goal)
        False -> None
      },
      week_intensity: intensities,
    ))
  })
}

/// `{"3": "high"}`, or `null` when nothing was set. Entries that are not a week number and a known level
/// are skipped, so one odd value does not hide the plan.
fn week_intensity_decoder() -> Decoder(Dict(Int, plan.Intensity)) {
  decode.one_of(
    decode.dict(decode.string, decode.string)
      |> decode.map(fn(raw) {
        dict.fold(raw, dict.new(), fn(acc, week, level) {
          case int.parse(week), plan.intensity_from_string(level) {
            Ok(n), Ok(intensity) if n >= 1 -> dict.insert(acc, n, intensity)
            _, _ -> acc
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
        use updated <- decode.optional_field("updated", "", decode.string)
        decode.success(Row(found, description, updated))
      })
  }
}

pub fn assignment(record: Dynamic) -> Result(Assignment, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use plan_id <- decode.field("plan", decode.string)
    use athlete <- decode.field("athlete", decode.string)
    use start <- decode.field("start_date", date_decoder())
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

/// A plan share, removed ones included (the row is reused when the plan is shared again).
pub fn share(record: Dynamic) -> Result(Share, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use plan_id <- decode.field("plan", decode.string)
    use user_id <- decode.field("user", decode.string)
    use user_name <- decode.optional_field("user_name", "", decode.string)
    use shared_by_name <- decode.optional_field(
      "shared_by_name",
      "",
      decode.string,
    )
    use deleted <- decode.optional_field("deleted", False, decode.bool)
    use updated <- decode.optional_field("updated", "", decode.string)
    decode.success(Share(
      id,
      plan_id,
      user_id,
      user_name,
      shared_by_name,
      deleted,
      updated,
    ))
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
    Error(Nil) -> decode.failure(plan.Easy, "Kind")
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
