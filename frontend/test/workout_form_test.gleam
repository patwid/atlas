import atlas/outbox
import atlas/plan.{Workout}
import atlas/workout_form.{Form, Row, Valid}
import gleam/dict
import gleam/option.{None, Some}
import gleam/string

fn form() -> workout_form.Form {
  Form("1", "1", "Easy run", plan.Easy, "", "", "", None)
}

pub fn decimals_accept_a_point_or_a_comma_test() {
  assert workout_form.parse_decimal("8") == Ok(8.0)
  assert workout_form.parse_decimal("8.5") == Ok(8.5)
  assert workout_form.parse_decimal("8,5") == Ok(8.5)
  assert workout_form.parse_decimal(" 10.234 ") == Ok(10.234)
  assert workout_form.parse_decimal(".5") == Ok(0.5)
  assert workout_form.parse_decimal("5.") == Ok(5.0)
  assert workout_form.parse_decimal("0") == Ok(0.0)
}

pub fn decimals_reject_everything_else_test() {
  assert workout_form.parse_decimal("") == Error(Nil)
  assert workout_form.parse_decimal("abc") == Error(Nil)
  assert workout_form.parse_decimal("-3") == Error(Nil)
  assert workout_form.parse_decimal("1.2.3") == Error(Nil)
  assert workout_form.parse_decimal("5 km") == Error(Nil)
}

pub fn durations_come_as_minutes_or_clock_style_test() {
  assert workout_form.parse_duration("45") == Ok(2700)
  assert workout_form.parse_duration("1:30") == Ok(5400)
  assert workout_form.parse_duration("0:45") == Ok(2700)
  assert workout_form.parse_duration("1:30:15") == Ok(5415)
  assert workout_form.parse_duration(" 90 ") == Ok(5400)
}

pub fn bad_durations_are_rejected_test() {
  assert workout_form.parse_duration("") == Error(Nil)
  assert workout_form.parse_duration("1:75") == Error(Nil)
  assert workout_form.parse_duration("1:30:75") == Error(Nil)
  assert workout_form.parse_duration("abc") == Error(Nil)
  assert workout_form.parse_duration("-5") == Error(Nil)
  assert workout_form.parse_duration("1:2:3:4") == Error(Nil)
}

pub fn formatting_for_the_form_round_trips_test() {
  assert workout_form.format_km(8000.0) == "8"
  assert workout_form.format_km(8500.0) == "8.5"
  assert workout_form.format_km(10_234.0) == "10.234"
  assert workout_form.format_km(5050.0) == "5.05"
  assert workout_form.format_duration(2700) == "45"
  assert workout_form.format_duration(5400) == "1:30"
  assert workout_form.format_duration(5415) == "1:30:15"
  assert workout_form.format_duration(3600) == "1:00"
  assert workout_form.parse_duration(workout_form.format_duration(5415))
    == Ok(5415)
}

pub fn a_minimal_workout_is_valid_test() {
  assert workout_form.validate(form())
    == Ok(Valid(0, "Easy run", plan.Easy, 0.0, 0, ""))
}

pub fn week_and_day_become_the_day_index_test() {
  assert workout_form.validate(Form(..form(), week: "3", day: "2"))
    == Ok(Valid(15, "Easy run", plan.Easy, 0.0, 0, ""))
  assert workout_form.validate(Form(..form(), week: "1", day: "7"))
    == Ok(Valid(6, "Easy run", plan.Easy, 0.0, 0, ""))
}

pub fn targets_are_converted_to_metres_and_seconds_test() {
  let typed =
    Form(
      ..form(),
      distance_km: "8,5",
      duration: "1:15",
      description: "  steady  ",
    )
  assert workout_form.validate(typed)
    == Ok(Valid(0, "Easy run", plan.Easy, 8500.0, 4500, "steady"))
}

pub fn every_field_has_its_own_error_test() {
  assert workout_form.validate(Form(..form(), week: "x"))
    == Error("Enter the week as a number.")
  assert workout_form.validate(Form(..form(), week: "0"))
    == Error("The week must be between 1 and 60.")
  assert workout_form.validate(Form(..form(), week: "61"))
    == Error("The week must be between 1 and 60.")
  assert workout_form.validate(Form(..form(), day: ""))
    == Error("Choose the day of the week.")
  assert workout_form.validate(Form(..form(), day: "8"))
    == Error("The day must be between 1 and 7.")
  assert workout_form.validate(Form(..form(), title: "  "))
    == Error("Give the workout a title.")
  assert workout_form.validate(Form(..form(), title: string.repeat("a", 201)))
    == Error("The title can have at most 200 characters.")
  assert workout_form.validate(
      Form(..form(), description: string.repeat("a", 5001)),
    )
    == Error("The description can have at most 5000 characters.")
  assert workout_form.validate(Form(..form(), distance_km: "far"))
    == Error("Enter the distance in kilometres, for example 8 or 8.5.")
  assert workout_form.validate(Form(..form(), distance_km: "1001"))
    == Error("The distance can be at most 1000 km.")
  assert workout_form.validate(Form(..form(), duration: "soon"))
    == Error(
      "Enter the duration in minutes (45) or as hours and minutes (1:30).",
    )
  assert workout_form.validate(Form(..form(), duration: "49:00"))
    == Error("The duration can be at most 48 hours.")
}

pub fn the_week_is_checked_first_so_one_mistake_gives_one_message_test() {
  assert workout_form.validate(Form("", "", "", plan.Easy, "x", "y", "", None))
    == Error("Enter the week as a number.")
}

fn row() -> workout_form.Row {
  Row(
    Workout("w1", "p1", 9, 2, "Tempo", plan.Tempo, Some(8000.0), Some(2700)),
    "3 x 10 min",
    "T1",
  )
}

pub fn editing_starts_from_the_stored_workout_test() {
  assert workout_form.from_row(row())
    == Form("2", "3", "Tempo", plan.Tempo, "8", "45", "3 x 10 min", None)
  let no_targets =
    Row(Workout("w2", "p1", 0, 0, "Rest", plan.Rest, None, None), "", "T")
  assert workout_form.from_row(no_targets)
    == Form("1", "1", "Rest", plan.Rest, "", "", "", None)
}

pub fn a_new_workout_carries_its_plan_position_and_values_test() {
  let valid = Valid(9, "Tempo", plan.Tempo, 8000.0, 2700, "3 x 10 min")
  assert workout_form.create_fields("p1", 2, valid)
    == dict.from_list([
      outbox.field_string("plan", "p1"),
      outbox.field_int("position", 2),
      outbox.field_int("day_index", 9),
      outbox.field_string("title", "Tempo"),
      outbox.field_string("kind", "tempo"),
      outbox.field_string("description", "3 x 10 min"),
      outbox.field_float("distance_m", 8000.0),
      outbox.field_int("duration_s", 2700),
    ])
}

pub fn an_edit_sends_only_what_changed_test() {
  let same = Valid(9, "Tempo", plan.Tempo, 8000.0, 2700, "3 x 10 min")
  assert workout_form.changed_fields(row(), same, 0) == dict.new()
  assert workout_form.changed_fields(
      row(),
      Valid(..same, title: "Tempo run"),
      0,
    )
    == dict.from_list([outbox.field_string("title", "Tempo run")])
  assert workout_form.changed_fields(
      row(),
      Valid(..same, distance_m: 9000.0, duration_s: 0),
      0,
    )
    == dict.from_list([
      outbox.field_float("distance_m", 9000.0),
      outbox.field_int("duration_s", 0),
    ])
  assert workout_form.changed_fields(
      row(),
      Valid(..same, kind: plan.Interval),
      0,
    )
    == dict.from_list([outbox.field_string("kind", "interval")])
}

pub fn moving_to_another_day_puts_the_workout_at_the_end_of_it_test() {
  let moved = Valid(10, "Tempo", plan.Tempo, 8000.0, 2700, "3 x 10 min")
  assert workout_form.changed_fields(row(), moved, 4)
    == dict.from_list([
      outbox.field_int("day_index", 10),
      outbox.field_int("position", 4),
    ])
}

pub fn labels_for_every_kind_test() {
  assert workout_form.kind_label(plan.Easy) == "Easy run"
  assert workout_form.kind_label(plan.Rest) == "Rest day"
  assert workout_form.kind_label(plan.Cross) == "Cross-training"
}

pub fn a_problem_names_its_field_test() {
  let assert Error(#("title", "Give the workout a title.")) =
    workout_form.validate_fields(workout_form.Form(
      "1",
      "1",
      "",
      plan.Easy,
      "",
      "",
      "",
      None,
    ))
  assert workout_form.error_field(workout_form.Form(
      "1",
      "1",
      "Run",
      plan.Easy,
      "x",
      "",
      "",
      None,
    ))
    == "distance"
  assert workout_form.error_field(workout_form.Form(
      "1",
      "1",
      "Run",
      plan.Easy,
      "",
      "",
      "",
      None,
    ))
    == ""
}
