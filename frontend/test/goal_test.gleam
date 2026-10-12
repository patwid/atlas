import atlas/goal.{Form, Goal}
import atlas/outbox
import gleam/dict

pub fn a_goal_needs_a_distance_and_a_time_test() {
  assert goal.parse(Form("10", "45")) == Ok(#(10_000.0, 2700))
  assert goal.parse(Form("21,1", "1:45:30")) == Ok(#(21_100.0, 6330))
  assert goal.parse(Form("42.195", "3:30")) == Ok(#(42_195.0, 12_600))
  let assert Error(#("distance", _)) = goal.parse(Form("", "45"))
  let assert Error(#("distance", _)) = goal.parse(Form("0", "45"))
  let assert Error(#("distance", _)) = goal.parse(Form("ten", "45"))
  let assert Error(#("distance", "The distance can be at most 1000 km.")) =
    goal.parse(Form("1000.5", "45"))
  let assert Error(#("time", _)) = goal.parse(Form("10", ""))
  let assert Error(#("time", _)) = goal.parse(Form("10", "0"))
  let assert Error(#("time", _)) = goal.parse(Form("10", "1:75"))
  let assert Error(#("time", "The time can be at most 48 hours.")) =
    goal.parse(Form("100", "48:00:01"))
}

pub fn a_saved_goal_fills_the_form_so_it_reads_back_the_same_test() {
  let g = Goal("g1", "me", 42_195.0, 12_630, "T")
  assert goal.to_form(g) == Form("42.195", "3:30:30")
  assert goal.parse(goal.to_form(g)) == Ok(#(42_195.0, 12_630))
  assert goal.to_form(Goal(..g, distance_m: 5000.0, time_s: 1170))
    == Form("5", "0:19:30")
}

pub fn the_fields_hold_the_owner_and_both_values_test() {
  assert goal.fields("me", 10_000.0, 2700)
    == dict.from_list([
      outbox.field_string("owner", "me"),
      outbox.field_float("distance_m", 10_000.0),
      outbox.field_int("time_s", 2700),
    ])
}

pub fn a_goal_reads_as_a_race_time_and_its_pace_test() {
  let g = Goal("g1", "me", 10_000.0, 2610, "T")
  assert goal.distance(g) == "10 km"
  assert goal.time_and_pace(g) == "43:30 · 4:21 /km"
  assert goal.summary(Goal(..g, distance_m: 21_097.5, time_s: 6300))
    == "21.098 km in 1:45:00"
}

pub fn only_ones_own_goals_shortest_first_test() {
  let marathon = Goal("a", "me", 42_195.0, 12_600, "T")
  let ten = Goal("b", "me", 10_000.0, 2700, "T")
  let faster_ten = Goal("c", "me", 10_000.0, 2500, "T")
  let athletes = Goal("d", "ana", 5000.0, 1200, "T")
  assert goal.of([marathon, athletes, ten, faster_ten], "me")
    == [faster_ten, ten, marathon]
}
