import atlas/assignments.{AssignmentsRead}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

pub fn live_assignments_are_read_and_others_left_out_test() {
  let stored = [
    dynamic_of(
      "{\"id\":\"a\",\"plan\":\"p1\",\"athlete\":\"me\",\"start_date\":\"\"}",
    ),
    dynamic_of(
      "{\"id\":\"gone\",\"plan\":\"p2\",\"athlete\":\"me\",\"start_date\":\"\",\"deleted\":true}",
    ),
    dynamic_of(
      "{\"id\":\"bad\",\"plan\":\"p3\",\"athlete\":\"me\",\"start_date\":\"soon\"}",
    ),
  ]
  let #(model, _) =
    assignments.update(assignments.new(), AssignmentsRead(Ok(stored)))
  assert model.loaded
  assert list.map(model.rows, fn(r) { r.assignment.id }) == ["a"]
}

pub fn a_failed_read_keeps_what_was_read_test() {
  let #(model, _) =
    assignments.update(assignments.new(), AssignmentsRead(Error(Nil)))
  assert model == assignments.new()
}
