import atlas/id
import atlas/outbox
import atlas/plan.{Workout}
import atlas/plan_copy
import atlas/random
import atlas/workout_form.{Row}
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string

fn source() -> plan.Plan {
  plan.new("src", "ana", "10k plan", "Build up slowly", plan.Public, "T")
}

fn row(id: String, day: Int, position: Int, title: String) -> workout_form.Row {
  Row(
    Workout(
      id,
      "src",
      day,
      position,
      title,
      plan.Tempo,
      Some(8000.0),
      Some(2700),
    ),
    "3 x 10 min",
    "T",
  )
}

pub fn the_copy_is_private_owned_by_the_copier_and_remembers_its_source_test() {
  let copy = plan_copy.build(source(), [], "me", fn() { "new-plan" })
  assert copy.plan_id == "new-plan"
  assert copy.plan_fields
    == dict.from_list([
      outbox.field_string("owner", "me"),
      outbox.field_string("title", "Copy of 10k plan"),
      outbox.field_string("description", "Build up slowly"),
      outbox.field_string("visibility", "private"),
      outbox.field_string("source_plan", "src"),
      outbox.field_int("base_weeks", 0),
      outbox.field_int("pre_competition_weeks", 0),
      outbox.field_int("competition_weeks", 0),
      outbox.field_float("weekly_distance_m", 0.0),
      #("week_intensity", "{}"),
    ])
  assert copy.workouts == []
}

pub fn phases_goal_and_intensities_are_copied_test() {
  let source =
    plan.Plan(
      ..source(),
      phases: plan.Phases(6, 3, 2),
      weekly_distance_m: option.Some(50_000.0),
      week_intensity: dict.from_list([#(2, plan.High)]),
    )
  let copy = plan_copy.build(source, [], "me", fn() { "x" })
  assert dict.get(copy.plan_fields, "base_weeks") == Ok("6")
  assert dict.get(copy.plan_fields, "competition_weeks") == Ok("2")
  assert dict.get(copy.plan_fields, "weekly_distance_m")
    == Ok(outbox.field_float("weekly_distance_m", 50_000.0).1)
  assert dict.get(copy.plan_fields, "week_intensity") == Ok("{\"2\":\"high\"}")
}

pub fn a_public_plan_is_copied_as_private_test() {
  let copy = plan_copy.build(source(), [], "me", fn() { "x" })
  assert dict.get(copy.plan_fields, "visibility") == Ok("\"private\"")
}

pub fn every_workout_is_copied_into_the_new_plan_test() {
  let copy =
    plan_copy.build(source(), [row("w1", 3, 1, "Tempo")], "me", fn() { "any" })
  let assert [#(_, fields)] = copy.workouts
  assert fields
    == dict.from_list([
      outbox.field_string("plan", "any"),
      outbox.field_int("day_index", 3),
      outbox.field_int("position", 1),
      outbox.field_string("title", "Tempo"),
      outbox.field_string("kind", "tempo"),
      outbox.field_string("description", "3 x 10 min"),
      outbox.field_float("distance_m", 8000.0),
      outbox.field_int("duration_s", 2700),
    ])
}

pub fn missing_targets_are_copied_as_zero_which_means_none_test() {
  let bare =
    Row(Workout("w", "src", 0, 0, "Rest", plan.Rest, None, None), "", "T")
  let copy = plan_copy.build(source(), [bare], "me", fn() { "x" })
  let assert [#(_, fields)] = copy.workouts
  assert dict.get(fields, "distance_m") == Ok("0")
  assert dict.get(fields, "duration_s") == Ok("0")
  assert dict.get(fields, "kind") == Ok("\"rest\"")
}

pub fn workouts_are_created_in_plan_order_after_the_plan_test() {
  // Given out of order, the workouts come back by day, then position, then ID.
  let rows = [
    row("c", 5, 0, "Third"),
    row("b", 0, 1, "Second"),
    row("a", 0, 0, "First"),
  ]
  let copy = plan_copy.build(source(), rows, "me", fn() { "id" })
  assert list.map(copy.workouts, fn(item) { dict.get(item.1, "title") })
    == [Ok("\"First\""), Ok("\"Second\""), Ok("\"Third\"")]
}

pub fn equal_days_and_positions_fall_back_to_the_id_so_the_order_is_stable_test() {
  let rows = [row("z", 1, 0, "Zed"), row("y", 1, 0, "Why")]
  let copy = plan_copy.build(source(), rows, "me", fn() { "id" })
  assert list.map(copy.workouts, fn(item) { dict.get(item.1, "title") })
    == [Ok("\"Why\""), Ok("\"Zed\"")]
}

pub fn the_plan_and_every_workout_get_their_own_valid_id_test() {
  let rows = list.map(list.repeat(Nil, 20), fn(_) { row("w", 0, 0, "A") })
  let copy = plan_copy.build(source(), rows, "me", random.new_id)
  let all = [copy.plan_id, ..list.map(copy.workouts, fn(item) { item.0 })]
  assert list.length(all) == 21
  assert list.length(list.unique(all)) == 21
  assert list.all(all, id.is_valid)
}

pub fn the_title_is_cut_to_fit_the_servers_limit_test() {
  let long = string.repeat("x", 200)
  let title = plan_copy.title(long)
  assert string.length(title) == 200
  assert string.starts_with(title, "Copy of xxx")
  assert plan_copy.title("Short") == "Copy of Short"
  assert string.length(plan_copy.title(string.repeat("y", 192))) == 200
  assert string.length(plan_copy.title(string.repeat("y", 191))) == 199
}

pub fn an_empty_plan_copies_to_an_empty_plan_test() {
  let copy =
    plan_copy.build(
      plan.new("e", "me", "Empty", "", plan.Private, "T"),
      [],
      "me",
      fn() { "n" },
    )
  assert dict.get(copy.plan_fields, "description") == Ok("\"\"")
  assert copy.workouts == []
}
