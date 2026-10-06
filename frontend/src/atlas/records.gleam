//// Reads synced records (the JSON objects PocketBase sends, kept as they are in IndexedDB) into the
//// domain types. A record that cannot be read is skipped, never a crash: a newer server may have
//// added values this client does not know yet.

import atlas/activity.{type Activity, Activity}
import atlas/date
import atlas/plan.{
  type Assignment, type Plan, type Workout, Assignment, Plan, Workout,
}
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
    decode.success(
      Plan(
        id: id,
        owner_id: owner,
        title: title,
        description: description,
        visibility: case visibility {
          "public" -> plan.Public
          _ -> plan.Private
        },
      ),
    )
  })
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

pub fn assignment(record: Dynamic) -> Result(Assignment, Nil) {
  run(record, {
    use id <- decode.field("id", decode.string)
    use plan_id <- decode.field("plan", decode.string)
    use athlete <- decode.field("athlete", decode.string)
    use start <- decode.field("start_date", date_decoder())
    decode.success(Assignment(id, plan_id, athlete, start))
  })
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
