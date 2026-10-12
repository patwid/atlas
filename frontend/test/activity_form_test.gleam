import atlas/activity.{Activity}
import atlas/activity_form.{Form, Row, Valid}
import atlas/date.{Date}
import atlas/outbox
import atlas/plan
import atlas/workout_form
import gleam/dict
import gleam/option.{None, Some}
import gleam/string

fn form() -> activity_form.Form {
  Form(
    "2026-10-01",
    "07:30",
    activity.Run,
    activity.Run,
    workout_form.Form(
      ..workout_form.empty_for(1, 1),
      distance_km: "8,5",
      duration: "45",
    ),
    None,
  )
}

fn typed(
  form: activity_form.Form,
  change: fn(workout_form.Form) -> workout_form.Form,
) -> activity_form.Form {
  activity_form.edit(form, change)
}

fn valid() -> activity_form.Valid {
  Valid(
    Date(2026, 10, 1),
    7,
    30,
    activity.Run,
    Some(plan.Run),
    "",
    8500.0,
    2700,
    "",
    None,
    0,
  )
}

pub fn nothing_is_worked_out_from_a_zone_test() {
  // A measured distance and time are both kept, whatever the zone (ADR 0121).
  let race =
    activity_form.choose(form(), "race")
    |> typed(fn(f) { workout_form.Form(..f, zone: "5") })
    |> typed(workout_form.set_segment(
      _,
      workout_form.Warmup,
      workout_form.DistanceField,
      "2",
    ))
  assert race.session.distance_km == "8,5"
  assert race.session.duration == "45"
  assert race.session.warmup.time == ""
}

pub fn the_form_starts_today_in_the_morning_as_a_run_test() {
  let empty = activity_form.empty_for(Date(2026, 10, 6))
  assert empty.date == "2026-10-06"
  assert empty.time == "07:00"
  assert empty.sport == activity.Run
  assert empty.session.kind == plan.Run
  assert activity_form.kind_value(empty) == "run"
}

pub fn a_complete_form_is_valid_test() {
  assert activity_form.validate(form()) == Ok(valid())
}

pub fn the_title_and_notes_can_be_given_test() {
  let full =
    typed(form(), fn(f) {
      workout_form.Form(..f, title: "  Morning run ", description: " Hilly ")
    })
  assert activity_form.validate(full)
    == Ok(Valid(..valid(), name: "Morning run", description: "Hilly"))
}

pub fn a_distance_alone_or_a_time_alone_is_enough_test() {
  let without = fn(distance, duration) {
    typed(form(), fn(f) {
      workout_form.Form(..f, distance_km: distance, duration: duration)
    })
  }
  assert activity_form.validate(without("8,5", ""))
    == Ok(Valid(..valid(), duration_s: 0))
  assert activity_form.validate(without("", "45"))
    == Ok(Valid(..valid(), distance_m: 0.0))
  assert activity_form.validate(without("", ""))
    == Error("Enter a distance or a duration, or both.")
  assert activity_form.validate(without("0", "0"))
    == Error("Enter a distance or a duration, or both.")
}

pub fn a_race_keeps_its_zone_warm_up_and_cool_down_test() {
  let race =
    activity_form.choose(form(), "race")
    |> typed(fn(f) { workout_form.Form(..f, zone: "5") })
    |> typed(workout_form.set_segment(
      _,
      workout_form.Warmup,
      workout_form.TimeField,
      "20",
    ))
  let assert Ok(saved) = activity_form.validate(race)
  assert saved.kind == Some(plan.Race)
  assert saved.sport == activity.Run
  assert saved.zone == 5
  let assert Some(intervals) = saved.intervals
  assert intervals.warmup.duration_s == 1200
}

pub fn intervals_without_a_distance_or_duration_take_their_parts_totals_test() {
  let intervals =
    activity_form.choose(form(), "interval")
    |> typed(fn(f) { workout_form.Form(..f, distance_km: "", duration: "") })
    |> typed(workout_form.type_reps(_, 0, "5"))
    |> typed(workout_form.set_segment(
      _,
      workout_form.Work(0),
      workout_form.DistanceField,
      "1000",
    ))
  let assert Ok(saved) = activity_form.validate(intervals)
  assert saved.kind == Some(plan.Interval)
  assert saved.distance_m == 5000.0
  assert saved.duration_s == 0
}

pub fn a_trail_run_stays_one_whatever_its_kind_test() {
  let trail =
    Form(..form(), stored_sport: activity.TrailRun, sport: activity.TrailRun)
  let chosen = activity_form.choose(trail, "interval")
  assert chosen.sport == activity.TrailRun
  assert chosen.session.kind == plan.Interval
  // A trail run is a run: its sport is not offered apart.
  assert activity_form.kind_options(trail)
    == [#("run", "Run"), #("interval", "Intervals"), #("race", "Race")]
}

pub fn another_sport_is_offered_and_kept_without_a_kind_test() {
  let ride = Form(..form(), stored_sport: activity.Ride, sport: activity.Ride)
  assert activity_form.kind_value(ride) == "ride"
  assert activity_form.kind_options(ride)
    == [
      #("run", "Run"),
      #("interval", "Intervals"),
      #("race", "Race"),
      #("ride", "Ride"),
    ]
  // A zone typed before has no say for another sport.
  let ride = typed(ride, fn(f) { workout_form.Form(..f, zone: "3") })
  assert activity_form.validate(ride)
    == Ok(Valid(..valid(), sport: activity.Ride, kind: None))
  let run = activity_form.choose(ride, "run")
  assert run.sport == activity.Run
  assert activity_form.choose(run, "ride").sport == activity.Ride
  // Only a kind or the stored sport can be chosen.
  assert activity_form.choose(run, "swim") == run
  assert activity_form.choose(run, "rest") == run
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
  assert activity_form.validate(
      typed(form(), fn(f) {
        workout_form.Form(..f, title: string.repeat("a", 201))
      }),
    )
    == Error("The title can have at most 200 characters.")
  assert activity_form.validate(
      typed(form(), fn(f) { workout_form.Form(..f, distance_km: "far") }),
    )
    == Error("Enter the distance in kilometres, for example 8 or 8.5.")
  assert activity_form.validate(
      typed(form(), fn(f) { workout_form.Form(..f, distance_km: "1001") }),
    )
    == Error("The distance can be at most 1000 km.")
  assert activity_form.validate(
      typed(form(), fn(f) { workout_form.Form(..f, duration: "soon") }),
    )
    == Error(
      "Enter the duration in minutes (45) or as hours and minutes (1:30).",
    )
  assert activity_form.validate(
      typed(form(), fn(f) { workout_form.Form(..f, duration: "49:00") }),
    )
    == Error("The duration can be at most 48 hours.")
}

pub fn a_new_manual_activity_is_stored_in_utc_with_its_owner_and_source_test() {
  let full =
    Valid(
      ..valid(),
      name: "Morning run",
      kind: Some(plan.Race),
      zone: 5,
      description: "Parkrun",
    )
  assert activity_form.create_fields("u1", full, 120)
    == dict.from_list([
      outbox.field_string("owner", "u1"),
      outbox.field_string("source", "manual"),
      outbox.field_string("started_at", "2026-10-01 05:30:00.000Z"),
      outbox.field_string("sport", "run"),
      outbox.field_string("kind", "race"),
      outbox.field_string("name", "Morning run"),
      outbox.field_float("distance_m", 8500.0),
      outbox.field_int("moving_time_s", 2700),
      outbox.field_int("elapsed_time_s", 2700),
      outbox.field_int("zone", 5),
      outbox.field_null("steps"),
      outbox.field_string("description", "Parkrun"),
    ])
}

pub fn an_early_start_east_of_utc_lands_on_the_previous_utc_day_test() {
  let early = Valid(..valid(), hour: 0, minute: 30)
  assert dict.get(activity_form.create_fields("u1", early, 120), "started_at")
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
    "",
    None,
    0,
    None,
    "",
  )
}

pub fn editing_shows_the_local_time_and_the_typed_forms_of_the_values_test() {
  let editing = activity_form.from_row(row(), 120)
  assert editing.date == "2026-10-01"
  assert editing.time == "07:30"
  assert editing.sport == activity.Run
  // Saved before activities had a kind: a run.
  assert editing.session.kind == plan.Run
  assert editing.session.title == "Morning run"
  assert editing.session.distance_km == "8.5"
  assert editing.session.duration == "45"
  // The same stored moment, seen from another time zone.
  assert activity_form.from_row(row(), -300).time == "00:30"
}

pub fn a_stored_kind_zone_and_notes_come_back_test() {
  let stored =
    Row(..row(), kind: Some(plan.Race), zone: 4, description: "Windy")
  let editing = activity_form.from_row(stored, 120)
  assert editing.session.kind == plan.Race
  assert editing.session.zone == "4"
  assert editing.session.description == "Windy"
}

pub fn unset_values_show_as_empty_fields_test() {
  let bare =
    Row(
      ..row(),
      activity: Activity(
        "x2",
        activity.Manual,
        "2026-10-01 05:30:00.000Z",
        activity.Walk,
        0.0,
        1800,
      ),
      name: "",
    )
  let editing = activity_form.from_row(bare, 0)
  assert editing.session.distance_km == ""
  assert editing.session.duration == "30"
  assert editing.session.title == ""
  assert activity_form.kind_value(editing) == "walk"
}

fn same() -> activity_form.Valid {
  Valid(..valid(), name: "Morning run")
}

pub fn an_unchanged_edit_sends_nothing_test() {
  assert activity_form.changed_fields(row(), same(), 120) == dict.new()
}

pub fn an_edit_sends_only_what_changed_test() {
  assert activity_form.changed_fields(
      row(),
      Valid(..same(), name: "Easy run"),
      120,
    )
    == dict.from_list([outbox.field_string("name", "Easy run")])
  assert activity_form.changed_fields(row(), Valid(..same(), minute: 45), 120)
    == dict.from_list([
      outbox.field_string("started_at", "2026-10-01 05:45:00.000Z"),
    ])
  assert activity_form.changed_fields(
      row(),
      Valid(..same(), duration_s: 3000),
      120,
    )
    == dict.from_list([
      outbox.field_int("moving_time_s", 3000),
      outbox.field_int("elapsed_time_s", 3000),
    ])
  assert activity_form.changed_fields(
      row(),
      Valid(..same(), kind: Some(plan.Interval), zone: 0),
      120,
    )
    == dict.from_list([outbox.field_string("kind", "interval")])
  assert activity_form.changed_fields(
      row(),
      Valid(..same(), zone: 2, description: "Easy"),
      120,
    )
    == dict.from_list([
      outbox.field_int("zone", 2),
      outbox.field_string("description", "Easy"),
    ])
}

pub fn an_activity_is_called_by_its_kind_or_sport_test() {
  assert activity_form.type_label(row()) == "Run"
  assert activity_form.type_label(Row(..row(), kind: Some(plan.Interval)))
    == "Intervals"
  let trail =
    Row(..row(), activity: Activity(..row().activity, sport: activity.TrailRun))
  assert activity_form.type_label(trail) == "Trail run"
  let ride =
    Row(
      ..row(),
      activity: Activity(..row().activity, sport: activity.Ride),
      kind: Some(plan.Race),
    )
  // Only a run has a kind.
  assert activity_form.type_label(ride) == "Ride"
  assert activity_form.targets(Row(..ride, zone: 3)) == ""
}

pub fn the_targets_read_as_a_workouts_test() {
  assert activity_form.targets(row()) == ""
  assert activity_form.targets(Row(..row(), zone: 2)) == "Zone 2"
  let intervals =
    plan.Intervals(
      plan.no_segment,
      [plan.Set(6, plan.Segment(4, 800.0, 0, None), plan.no_segment)],
      plan.no_segment,
    )
  assert activity_form.targets(
      Row(..row(), kind: Some(plan.Interval), intervals: Some(intervals)),
    )
    == "6 × 800 m (Zone 4)"
}

pub fn labels_for_every_sport_test() {
  assert activity_form.sport_label(activity.Run) == "Run"
  assert activity_form.sport_label(activity.TrailRun) == "Trail run"
  assert activity_form.sport_label(activity.Strength) == "Strength"
}

fn strava_row(
  source: activity.Source,
  external_id: String,
) -> activity_form.Row {
  Row(
    Activity(
      "x",
      source,
      "2026-10-01 05:30:00.000Z",
      activity.Run,
      5000.0,
      1500,
    ),
    "u1",
    "",
    0.0,
    0,
    "T",
    external_id,
    None,
    0,
    None,
    "",
  )
}

pub fn a_strava_activity_links_back_to_strava_test() {
  assert activity_form.strava_url(strava_row(activity.Strava, "1234567890"))
    == Some("https://www.strava.com/activities/1234567890")
}

pub fn only_strava_activities_with_a_numeric_id_get_a_link_test() {
  assert activity_form.strava_url(strava_row(activity.Manual, "1234567890"))
    == None
  assert activity_form.strava_url(strava_row(activity.Fit, "abc")) == None
  assert activity_form.strava_url(strava_row(activity.Strava, "")) == None
  // Nothing but digits ever reaches the address.
  assert activity_form.strava_url(strava_row(activity.Strava, "12/../x"))
    == None
  assert activity_form.strava_url(strava_row(activity.Strava, "12 34")) == None
  assert activity_form.strava_url(strava_row(
      activity.Strava,
      "https://evil.example",
    ))
    == None
  assert activity_form.strava_url(strava_row(activity.Strava, "1e5")) == None
}

pub fn a_problem_names_its_field_test() {
  assert activity_form.error_field(Form(..form(), date: "")) == "date"
  assert activity_form.error_field(Form(..form(), time: "")) == "time"
  assert activity_form.error_field(
      typed(form(), fn(f) { workout_form.Form(..f, distance_km: "far") }),
    )
    == "distance"
  assert activity_form.error_field(
      typed(form(), fn(f) {
        workout_form.Form(..f, title: string.repeat("a", 201))
      }),
    )
    == "title"
  assert activity_form.error_field(form()) == ""
}
