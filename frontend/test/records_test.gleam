import atlas/activity
import atlas/date.{Date}
import atlas/plan.{Assignment, Plan, Workout}
import atlas/records
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}

fn parse(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

// What PocketBase sends (shapes pinned by backend/tests/contract.test.mjs).
const plan_json =
  "{\"collectionId\":\"pbc_1\",\"deleted\":false,\"description\":\"Build up\",\"id\":\"p1\",\"owner\":\"u1\",\"source_plan\":\"\",\"title\":\"10k plan\",\"updated\":\"2026-10-06 08:30:35.585Z\",\"visibility\":\"public\"}"

pub fn reads_a_plan_test() {
  assert records.plan(parse(plan_json))
    == Ok(Plan(
      "p1",
      "u1",
      "10k plan",
      "Build up",
      plan.Public,
      "2026-10-06 08:30:35.585Z",
    ))
}

pub fn a_plan_made_offline_has_fewer_fields_test() {
  assert records.plan(parse("{\"id\":\"p2\",\"title\":\"New\"}"))
    == Ok(Plan("p2", "", "New", "", plan.Private, ""))
}

pub fn a_plan_without_a_title_is_skipped_test() {
  assert records.plan(parse("{\"id\":\"p3\"}")) == Error(Nil)
  assert records.plan(parse("[]")) == Error(Nil)
  assert records.plan(parse("null")) == Error(Nil)
}

pub fn reads_a_workout_and_treats_zero_targets_as_none_test() {
  let full =
    "{\"id\":\"w1\",\"plan\":\"p1\",\"day_index\":3,\"position\":1,\"title\":\"Tempo\",\"kind\":\"tempo\",\"distance_m\":8000,\"duration_s\":2700}"
  assert records.workout(parse(full))
    == Ok(Workout(
      "w1",
      "p1",
      3,
      1,
      "Tempo",
      plan.Tempo,
      Some(8000.0),
      Some(2700),
    ))
  let empty =
    "{\"id\":\"w2\",\"plan\":\"p1\",\"day_index\":0,\"position\":0,\"title\":\"Rest\",\"kind\":\"rest\",\"distance_m\":0,\"duration_s\":0}"
  assert records.workout(parse(empty))
    == Ok(Workout("w2", "p1", 0, 0, "Rest", plan.Rest, None, None))
}

pub fn numbers_are_read_whether_whole_or_fractional_test() {
  let fractional =
    "{\"id\":\"w3\",\"plan\":\"p1\",\"title\":\"x\",\"kind\":\"easy\",\"distance_m\":10234.5,\"day_index\":2.0}"
  let assert Ok(w) = records.workout(parse(fractional))
  assert w.distance_m == Some(10_234.5)
  assert w.day_index == 2
}

pub fn a_workout_with_an_unknown_kind_is_skipped_test() {
  assert records.workout(parse(
      "{\"id\":\"w\",\"plan\":\"p\",\"title\":\"x\",\"kind\":\"yoga\"}",
    ))
    == Error(Nil)
}

pub fn reads_an_assignment_test() {
  let text =
    "{\"id\":\"a1\",\"plan\":\"p1\",\"athlete\":\"u1\",\"assigned_by\":\"u2\",\"start_date\":\"2026-11-02\"}"
  assert records.assignment(parse(text))
    == Ok(Assignment("a1", "p1", "u1", Date(2026, 11, 2)))
  assert records.assignment(parse(
      "{\"id\":\"a\",\"plan\":\"p\",\"athlete\":\"u\",\"start_date\":\"02.11.2026\"}",
    ))
    == Error(Nil)
}

pub fn reads_an_activity_test() {
  let text =
    "{\"id\":\"x1\",\"source\":\"strava\",\"started_at\":\"2026-10-01 07:00:00.000Z\",\"sport\":\"trail_run\",\"distance_m\":10234.5,\"moving_time_s\":3000,\"laps\":[{\"index\":1}]}"
  assert records.activity(parse(text))
    == Ok(activity.Activity(
      "x1",
      activity.Strava,
      "2026-10-01 07:00:00.000Z",
      activity.TrailRun,
      10_234.5,
      3000,
    ))
  let whole =
    "{\"id\":\"x2\",\"source\":\"fit\",\"started_at\":\"2026-10-01 07:00:00.000Z\",\"sport\":\"run\",\"distance_m\":5000}"
  let assert Ok(a) = records.activity(parse(whole))
  assert a.distance_m == 5000.0
  assert a.moving_time_s == 0
}

pub fn live_drops_deleted_and_unreadable_records_test() {
  let items = [
    parse(plan_json),
    parse("{\"id\":\"gone\",\"title\":\"Deleted\",\"deleted\":true}"),
    parse("{\"id\":\"broken\"}"),
    parse("{\"id\":\"p9\",\"title\":\"Other\",\"deleted\":false}"),
  ]
  let ids = case records.live(items, records.plan) {
    [a, b] -> [a.id, b.id]
    _ -> []
  }
  assert ids == ["p1", "p9"]
  assert records.is_deleted(parse("{\"deleted\":true}"))
  assert !records.is_deleted(parse("{\"id\":\"x\"}"))
}
