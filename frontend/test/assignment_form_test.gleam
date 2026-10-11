import atlas/assignment_form.{Form, Row, Valid}
import atlas/date.{Date}
import atlas/outbox
import atlas/plan.{Assignment}
import gleam/dict
import gleam/option.{None, Some}

fn form(athlete: String, start: String) -> assignment_form.Form {
  Form(athlete, start, False, None)
}

pub fn starting_ones_own_dated_plan_follows_its_date_test() {
  assert assignment_form.empty_for(
      "u1",
      Some(Date(2026, 11, 4)),
      True,
      Date(2026, 10, 6),
    )
    == Form("u1", "2026-11-04", True, None)
  let assert Ok(valid) = assignment_form.validate(Form("u1", "", True, None))
  assert valid == Valid("u1", None)
  assert assignment_form.create_fields("p1", "u1", valid)
    |> dict.get("start_date")
    == Ok("\"\"")
}

pub fn someone_elses_plan_gets_its_own_date_test() {
  // The plan's date while it is still ahead.
  assert assignment_form.empty_for(
      "u1",
      Some(Date(2026, 11, 4)),
      False,
      Date(2026, 10, 6),
    )
    == Form("u1", "2026-11-04", False, None)
  // The coming Monday once it has passed, or for a plan without one.
  assert assignment_form.empty_for(
      "u1",
      Some(Date(2026, 9, 2)),
      False,
      Date(2026, 10, 6),
    )
    == Form("u1", "2026-10-12", False, None)
  assert assignment_form.empty_for("u1", None, True, Date(2026, 10, 12))
    == Form("u1", "2026-10-12", False, None)
}

pub fn a_valid_form_gives_the_athlete_and_the_date_test() {
  assert assignment_form.validate(form("u1", "2026-11-02"))
    == Ok(Valid("u1", Some(Date(2026, 11, 2))))
}

pub fn a_start_date_in_the_past_is_fine_test() {
  assert assignment_form.validate(form("u1", "2025-01-06"))
    == Ok(Valid("u1", Some(Date(2025, 1, 6))))
}

pub fn bad_input_gets_a_message_test() {
  assert assignment_form.validate(form("", "2026-11-02"))
    == Error("Choose who the plan is for.")
  assert assignment_form.validate(form("u1", "")) == Error("Pick a start date.")
  assert assignment_form.validate(form("u1", "02.11.2026"))
    == Error("Pick a start date.")
  assert assignment_form.validate(form("u1", "2026-02-30"))
    == Error("Pick a start date.")
}

pub fn absurd_years_are_refused_test() {
  assert assignment_form.validate(form("u1", "1999-12-31"))
    == Error("The start date must be between the years 2000 and 2100.")
  assert assignment_form.validate(form("u1", "2101-01-01"))
    == Error("The start date must be between the years 2000 and 2100.")
  assert assignment_form.validate(form("u1", "2000-01-01"))
    == Ok(Valid("u1", Some(Date(2000, 1, 1))))
  assert assignment_form.validate(form("u1", "2100-12-31"))
    == Ok(Valid("u1", Some(Date(2100, 12, 31))))
}

pub fn a_new_assignment_names_the_plan_the_athlete_and_who_made_it_test() {
  assert assignment_form.create_fields(
      "p1",
      "coach1",
      Valid("athlete1", Some(Date(2026, 11, 2))),
    )
    == dict.from_list([
      outbox.field_string("plan", "p1"),
      outbox.field_string("athlete", "athlete1"),
      outbox.field_string("assigned_by", "coach1"),
      outbox.field_string("start_date", "2026-11-02"),
    ])
}

fn row() -> assignment_form.Row {
  Row(Assignment("a1", "p1", "u1", Some(Date(2026, 11, 2))), "u1", "T1")
}

pub fn only_a_changed_start_date_is_sent_test() {
  assert assignment_form.changed_fields(
      row(),
      Valid("u1", Some(Date(2026, 11, 9))),
    )
    == dict.from_list([outbox.field_string("start_date", "2026-11-09")])
  assert assignment_form.changed_fields(
      row(),
      Valid("u1", Some(Date(2026, 11, 2))),
    )
    == dict.new()
}

pub fn editing_starts_from_the_stored_assignment_test() {
  assert assignment_form.from_row(row(), Some(Date(2026, 12, 7)))
    == Form("u1", "2026-11-02", False, None)
}

pub fn a_following_assignment_gets_a_date_of_its_own_when_changed_test() {
  let following = Row(Assignment("a1", "p1", "u1", None), "coach", "T1")
  assert assignment_form.from_row(following, Some(Date(2026, 12, 7)))
    == Form("u1", "2026-12-07", False, None)
  assert assignment_form.changed_fields(
      following,
      Valid("u1", Some(Date(2026, 12, 7))),
    )
    == dict.from_list([outbox.field_string("start_date", "2026-12-07")])
}

pub fn a_problem_names_its_field_test() {
  assert assignment_form.error_field(form("", "2026-11-02")) == "athlete"
  assert assignment_form.error_field(form("u1", "")) == "start"
  assert assignment_form.error_field(form("u1", "2026-11-02")) == ""
}
