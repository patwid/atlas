import atlas/activity.{Activity}
import atlas/activity_form.{Form, Row, Valid}
import atlas/date.{Date}
import atlas/outbox
import gleam/dict
import gleam/option.{None}
import gleam/string

fn form() -> activity_form.Form {
  Form("2026-10-01", "07:30", activity.Run, "", "8,5", "45", "", "", None)
}

pub fn the_form_starts_today_in_the_morning_test() {
  assert activity_form.empty_for(Date(2026, 10, 6))
    == Form("2026-10-06", "07:00", activity.Run, "", "", "", "", "", None)
}

pub fn a_complete_form_is_valid_test() {
  assert activity_form.validate(form())
    == Ok(Valid(Date(2026, 10, 1), 7, 30, activity.Run, "", 8500.0, 2700, 0, 0))
}

pub fn every_optional_field_can_be_given_test() {
  let full =
    Form(
      ..form(),
      name: "  Morning run ",
      elevation_m: "120",
      avg_hr: "152",
      duration: "1:05:30",
    )
  assert activity_form.validate(full)
    == Ok(Valid(
      Date(2026, 10, 1),
      7,
      30,
      activity.Run,
      "Morning run",
      8500.0,
      3930,
      120,
      152,
    ))
}

pub fn a_distance_alone_or_a_time_alone_is_enough_test() {
  assert activity_form.validate(Form(..form(), duration: ""))
    == Ok(Valid(Date(2026, 10, 1), 7, 30, activity.Run, "", 8500.0, 0, 0, 0))
  assert activity_form.validate(Form(..form(), distance_km: ""))
    == Ok(Valid(Date(2026, 10, 1), 7, 30, activity.Run, "", 0.0, 2700, 0, 0))
  assert activity_form.validate(Form(..form(), distance_km: "", duration: ""))
    == Error("Enter a distance or a time, or both.")
  assert activity_form.validate(Form(..form(), distance_km: "0", duration: "0"))
    == Error("Enter a distance or a time, or both.")
}

pub fn times_are_read_strictly_test() {
  assert activity_form.parse_time("07:30") == Ok(#(7, 30))
  assert activity_form.parse_time("7:30") == Ok(#(7, 30))
  assert activity_form.parse_time("23:59") == Ok(#(23, 59))
  assert activity_form.parse_time("00:00") == Ok(#(0, 0))
  assert activity_form.parse_time("24:00") == Error(Nil)
  assert activity_form.parse_time("07:60") == Error(Nil)
  assert activity_form.parse_time("07:5") == Error(Nil)
  assert activity_form.parse_time("0730") == Error(Nil)
  assert activity_form.parse_time("") == Error(Nil)
}

pub fn each_field_has_its_own_message_test() {
  assert activity_form.validate(Form(..form(), date: ""))
    == Error("Pick the day of the activity.")
  assert activity_form.validate(Form(..form(), date: "01.10.2026"))
    == Error("Pick the day of the activity.")
  assert activity_form.validate(Form(..form(), date: "1999-12-31"))
    == Error("The date must be between the years 2000 and 2100.")
  assert activity_form.validate(Form(..form(), time: ""))
    == Error("Enter the start time as hours and minutes, for example 07:30.")
  assert activity_form.validate(Form(..form(), name: string.repeat("a", 201)))
    == Error("The name can have at most 200 characters.")
  assert activity_form.validate(Form(..form(), distance_km: "far"))
    == Error("Enter the distance in kilometres, for example 8 or 8.5.")
  assert activity_form.validate(Form(..form(), distance_km: "1001"))
    == Error("The distance can be at most 1000 km.")
  assert activity_form.validate(Form(..form(), duration: "soon"))
    == Error("Enter the time in minutes (45) or as hours and minutes (1:30).")
  assert activity_form.validate(Form(..form(), duration: "49:00"))
    == Error("The time can be at most 48 hours.")
  assert activity_form.validate(Form(..form(), elevation_m: "high"))
    == Error("The elevation must be a whole number from 0 to 10000.")
  assert activity_form.validate(Form(..form(), avg_hr: "20"))
    == Error("The average heart rate must be a whole number from 30 to 250.")
  assert activity_form.validate(Form(..form(), avg_hr: "251"))
    == Error("The average heart rate must be a whole number from 30 to 250.")
}

pub fn a_new_manual_activity_is_stored_in_utc_with_its_owner_and_source_test() {
  let valid =
    Valid(
      Date(2026, 10, 1),
      7,
      30,
      activity.Run,
      "Morning run",
      8500.0,
      2700,
      120,
      152,
    )
  assert activity_form.create_fields("u1", valid, 120)
    == dict.from_list([
      outbox.field_string("owner", "u1"),
      outbox.field_string("source", "manual"),
      outbox.field_string("started_at", "2026-10-01 05:30:00.000Z"),
      outbox.field_string("sport", "run"),
      outbox.field_string("name", "Morning run"),
      outbox.field_float("distance_m", 8500.0),
      outbox.field_int("moving_time_s", 2700),
      outbox.field_int("elapsed_time_s", 2700),
      outbox.field_int("elevation_gain_m", 120),
      outbox.field_int("avg_hr", 152),
    ])
}

pub fn an_early_start_east_of_utc_lands_on_the_previous_utc_day_test() {
  let valid = Valid(Date(2026, 10, 1), 0, 30, activity.Run, "", 5000.0, 0, 0, 0)
  assert dict.get(activity_form.create_fields("u1", valid, 120), "started_at")
    == Ok("\"2026-09-30 22:30:00.000Z\"")
}

fn row() -> activity_form.Row {
  Row(
    Activity(
      "x1",
      activity.Manual,
      "2026-10-01 05:30:00.000Z",
      activity.Run,
      8500.0,
      2700,
    ),
    "u1",
    "Morning run",
    120.0,
    152,
    "T1",
  )
}

pub fn editing_shows_the_local_time_and_the_typed_forms_of_the_values_test() {
  assert activity_form.from_row(row(), 120)
    == Form(
      "2026-10-01",
      "07:30",
      activity.Run,
      "Morning run",
      "8.5",
      "45",
      "120",
      "152",
      None,
    )
  // The same stored moment, seen from another time zone.
  let assert Form("2026-10-01", "00:30", ..) =
    activity_form.from_row(row(), -300)
}

pub fn unset_values_show_as_empty_fields_test() {
  let bare =
    Row(
      Activity(
        "x2",
        activity.Manual,
        "2026-10-01 05:30:00.000Z",
        activity.Walk,
        0.0,
        1800,
      ),
      "u1",
      "",
      0.0,
      0,
      "T",
    )
  assert activity_form.from_row(bare, 0)
    == Form("2026-10-01", "05:30", activity.Walk, "", "", "30", "", "", None)
}

pub fn an_unchanged_edit_sends_nothing_test() {
  let same =
    Valid(
      Date(2026, 10, 1),
      7,
      30,
      activity.Run,
      "Morning run",
      8500.0,
      2700,
      120,
      152,
    )
  assert activity_form.changed_fields(row(), same, 120) == dict.new()
}

pub fn an_edit_sends_only_what_changed_test() {
  let same =
    Valid(
      Date(2026, 10, 1),
      7,
      30,
      activity.Run,
      "Morning run",
      8500.0,
      2700,
      120,
      152,
    )
  assert activity_form.changed_fields(
      row(),
      Valid(..same, name: "Easy run"),
      120,
    )
    == dict.from_list([outbox.field_string("name", "Easy run")])
  assert activity_form.changed_fields(row(), Valid(..same, minute: 45), 120)
    == dict.from_list([
      outbox.field_string("started_at", "2026-10-01 05:45:00.000Z"),
    ])
  assert activity_form.changed_fields(
      row(),
      Valid(..same, duration_s: 3000),
      120,
    )
    == dict.from_list([
      outbox.field_int("moving_time_s", 3000),
      outbox.field_int("elapsed_time_s", 3000),
    ])
  assert activity_form.changed_fields(
      row(),
      Valid(..same, sport: activity.Walk, avg_hr: 0),
      120,
    )
    == dict.from_list([
      outbox.field_string("sport", "walk"),
      outbox.field_int("avg_hr", 0),
    ])
}

pub fn labels_for_every_sport_test() {
  assert activity_form.sport_label(activity.Run) == "Run"
  assert activity_form.sport_label(activity.TrailRun) == "Trail run"
  assert activity_form.sport_label(activity.Strength) == "Strength"
}
