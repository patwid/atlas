import atlas/outbox
import atlas/pace_zones
import atlas/plan.{Workout}
import atlas/workout_form.{Form, NeitherTyped, Row, Valid}
import gleam/dict
import gleam/option.{None, Some}
import gleam/string

fn form() -> workout_form.Form {
  Form(
    "1",
    "1",
    "Easy run",
    plan.Run,
    "",
    "",
    "",
    workout_form.blank_segment,
    [workout_form.blank_set],
    workout_form.blank_segment,
    "",
    NeitherTyped,
    0,
    [],
    None,
  )
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
    == Ok(Valid(0, "Easy run", plan.Run, 0.0, 0, "", None, 0))
}

pub fn week_and_day_become_the_day_index_test() {
  assert workout_form.validate(Form(..form(), week: "3", day: "2"))
    == Ok(Valid(15, "Easy run", plan.Run, 0.0, 0, "", None, 0))
  assert workout_form.validate(Form(..form(), week: "1", day: "7"))
    == Ok(Valid(6, "Easy run", plan.Run, 0.0, 0, "", None, 0))
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
    == Ok(Valid(0, "Easy run", plan.Run, 8500.0, 4500, "steady", None, 0))
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
    == Error("The notes can have at most 5000 characters.")
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
  assert workout_form.validate(Form(
      "",
      "",
      "",
      plan.Run,
      "x",
      "y",
      "",
      workout_form.blank_segment,
      [workout_form.blank_set],
      workout_form.blank_segment,
      "",
      NeitherTyped,
      0,
      [],
      None,
    ))
    == Error("Enter the week as a number.")
}

fn row() -> workout_form.Row {
  Row(
    Workout("w1", "p1", 9, 2, "Tempo", plan.Run, Some(8000.0), Some(2700)),
    "3 x 10 min",
    None,
    0,
    "T1",
  )
}

pub fn editing_starts_from_the_stored_workout_test() {
  assert workout_form.from_row(row())
    == Form(
      "2",
      "3",
      "Tempo",
      plan.Run,
      "8",
      "45",
      "3 x 10 min",
      workout_form.blank_segment,
      [workout_form.blank_set],
      workout_form.blank_segment,
      "",
      NeitherTyped,
      0,
      [],
      None,
    )
  let no_targets =
    Row(
      Workout("w2", "p1", 0, 0, "Rest", plan.Rest, None, None),
      "",
      None,
      0,
      "T",
    )
  assert workout_form.from_row(no_targets)
    == Form(
      "1",
      "1",
      "Rest",
      plan.Rest,
      "",
      "",
      "",
      workout_form.blank_segment,
      [workout_form.blank_set],
      workout_form.blank_segment,
      "",
      NeitherTyped,
      0,
      [],
      None,
    )
}

pub fn a_new_workout_carries_its_plan_position_and_values_test() {
  let valid = Valid(9, "Tempo", plan.Run, 8000.0, 2700, "3 x 10 min", None, 0)
  assert workout_form.create_fields("p1", 2, valid)
    == dict.from_list([
      outbox.field_string("plan", "p1"),
      outbox.field_int("position", 2),
      outbox.field_int("day_index", 9),
      outbox.field_string("title", "Tempo"),
      outbox.field_string("kind", "run"),
      outbox.field_string("description", "3 x 10 min"),
      outbox.field_float("distance_m", 8000.0),
      outbox.field_int("duration_s", 2700),
      outbox.field_null("steps"),
      outbox.field_int("zone", 0),
    ])
}

pub fn an_edit_sends_only_what_changed_test() {
  let same = Valid(9, "Tempo", plan.Run, 8000.0, 2700, "3 x 10 min", None, 0)
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
  let moved = Valid(10, "Tempo", plan.Run, 8000.0, 2700, "3 x 10 min", None, 0)
  assert workout_form.changed_fields(row(), moved, 4)
    == dict.from_list([
      outbox.field_int("day_index", 10),
      outbox.field_int("position", 4),
    ])
}

pub fn labels_for_every_kind_test() {
  assert workout_form.kind_label(plan.Run) == "Run"
  assert workout_form.kind_label(plan.Interval) == "Intervals"
  assert workout_form.kind_label(plan.Race) == "Race"
  assert workout_form.kind_label(plan.Rest) == "Rest day"
}

pub fn a_problem_names_its_field_test() {
  let assert Error(#("title", "Give the workout a title.")) =
    workout_form.validate_fields(workout_form.Form(
      "1",
      "1",
      "",
      plan.Run,
      "",
      "",
      "",
      workout_form.blank_segment,
      [workout_form.blank_set],
      workout_form.blank_segment,
      "",
      NeitherTyped,
      0,
      [],
      None,
    ))
  assert workout_form.error_field(workout_form.Form(
      "1",
      "1",
      "Run",
      plan.Run,
      "x",
      "",
      "",
      workout_form.blank_segment,
      [workout_form.blank_set],
      workout_form.blank_segment,
      "",
      NeitherTyped,
      0,
      [],
      None,
    ))
    == "distance"
  assert workout_form.error_field(workout_form.Form(
      "1",
      "1",
      "Run",
      plan.Run,
      "",
      "",
      "",
      workout_form.blank_segment,
      [workout_form.blank_set],
      workout_form.blank_segment,
      "",
      NeitherTyped,
      0,
      [],
      None,
    ))
    == ""
}

fn segment(zone: String, distance: String, time: String) {
  workout_form.SegmentForm(zone, distance, time, NeitherTyped, "", "")
}

fn intervals_form() -> workout_form.Form {
  Form(..form(), kind: plan.Interval, sets: [
    workout_form.SetForm(
      "6",
      segment("4", "800", "2:50"),
      segment("", "", "90"),
    ),
  ])
}

fn with_set(change: fn(workout_form.SetForm) -> workout_form.SetForm) {
  let assert [set] = intervals_form().sets
  Form(..intervals_form(), sets: [change(set)])
}

fn work(zone: Int, distance: Float, time: Int) -> plan.Segment {
  plan.Segment(zone, distance, time, None)
}

pub fn an_interval_workout_carries_its_parts_test() {
  let assert Ok(valid) = workout_form.validate(intervals_form())
  assert valid.intervals
    == Some(plan.Intervals(
      plan.no_segment,
      [plan.Set(6, work(4, 800.0, 170), work(0, 0.0, 90))],
      plan.no_segment,
    ))
  // The workout has no zone of its own: its parts have one (ADR 0117).
  assert valid.zone == 0
  let assert Ok(valid) =
    workout_form.validate(
      Form(
        ..intervals_form(),
        warmup: segment("1", "2", "15"),
        cooldown: segment("", "", "10"),
        sets: [
          workout_form.SetForm(
            "3",
            segment("5", "400", ""),
            segment("1", "200", ""),
          ),
          // An empty set is left out.
          workout_form.blank_set,
          workout_form.SetForm(
            "2",
            segment("3", "", "5:00"),
            segment("", "", ""),
          ),
        ],
      ),
    )
  assert valid.intervals
    == Some(plan.Intervals(
      work(1, 2000.0, 900),
      [
        plan.Set(3, work(5, 400.0, 0), work(1, 200.0, 0)),
        plan.Set(2, work(3, 0.0, 300), plan.no_segment),
      ],
      work(0, 0.0, 600),
    ))
  assert valid.zone == 0
}

pub fn the_parts_are_optional_and_only_for_intervals_test() {
  let assert Ok(valid) =
    workout_form.validate(Form(..form(), kind: plan.Interval))
  assert valid.intervals == None
  // Typed, then the kind changed: they are not kept.
  let assert Ok(valid) =
    workout_form.validate(Form(..intervals_form(), kind: plan.Run))
  assert valid.intervals == None
  // A zone chosen while it was a run is not kept.
  let assert Ok(valid) =
    workout_form.validate(Form(..form(), kind: plan.Interval, zone: "3"))
  assert valid.zone == 0
}

pub fn a_race_has_a_warm_up_and_cool_down_but_no_sets_test() {
  let race =
    Form(
      ..intervals_form(),
      kind: plan.Race,
      zone: "5",
      distance_km: "10",
      warmup: segment("1", "", "20"),
      cooldown: segment("", "2", ""),
    )
  let assert Ok(valid) = workout_form.validate(race)
  // The sets typed while it was an interval workout are not kept (ADR 0119).
  assert valid.intervals
    == Some(plan.Intervals(work(1, 0.0, 1200), [], work(0, 2000.0, 0)))
  // A race keeps its own zone and distance.
  assert valid.zone == 5
  assert valid.distance_m == 10_000.0
  assert workout_form.steps_field(valid.intervals)
    == #(
      "steps",
      "{\"v\":2,\"warmup\":{\"zone\":1,\"duration_s\":1200},\"cooldown\":{\"distance_m\":2000}}",
    )
  // Without either there are no steps.
  let assert Ok(valid) =
    workout_form.validate(
      Form(
        ..race,
        warmup: workout_form.blank_segment,
        cooldown: workout_form.blank_segment,
      ),
    )
  assert valid.intervals == None
  assert workout_form.validate_fields(
      Form(..race, warmup: segment("1", "", "")),
    )
    == Error(#(
      "warmup_distance",
      "Give the warm-up a distance, a time or both.",
    ))
}

pub fn problems_with_the_parts_name_their_field_test() {
  let problem = fn(f) { workout_form.validate_fields(f) }
  let reps = fn(text) {
    with_set(fn(set) { workout_form.SetForm(..set, reps: text) })
  }
  let rep = fn(s) { with_set(fn(set) { workout_form.SetForm(..set, work: s) }) }
  let recovery = fn(s) {
    with_set(fn(set) { workout_form.SetForm(..set, recovery: s) })
  }
  assert problem(reps(""))
    == Error(#("set1_reps", "Enter how many repetitions."))
  assert problem(reps("six"))
    == Error(#("set1_reps", "Enter the repetitions as a whole number."))
  assert problem(reps("0"))
    == Error(#("set1_reps", "The repetitions must be between 1 and 100."))
  assert problem(reps("101"))
    == Error(#("set1_reps", "The repetitions must be between 1 and 100."))
  assert problem(rep(segment("", "far", "")))
    == Error(#(
      "set1_work_distance",
      "Enter the distance in metres, for example 400.",
    ))
  assert problem(rep(segment("", "20001", "")))
    == Error(#(
      "set1_work_distance",
      "The distance of a rep can be at most 20000 m.",
    ))
  assert problem(rep(segment("", "", "1:75")))
    == Error(#(
      "set1_work_time",
      "Enter the time in seconds (90) or as minutes and seconds (1:30).",
    ))
  assert problem(recovery(segment("", "", "61:00")))
    == Error(#(
      "set1_recovery_time",
      "The time of a recovery can be at most 60 minutes.",
    ))
  assert problem(rep(segment("4", "", "")))
    == Error(#(
      "set1_work_distance",
      "Give each rep a distance, a time or both.",
    ))
  assert problem(recovery(segment("1", "", "")))
    == Error(#(
      "set1_recovery_distance",
      "Give the recovery a distance, a time or both.",
    ))
  assert problem(Form(..intervals_form(), warmup: segment("", "51", "")))
    == Error(#("warmup_distance", "The warm-up can be at most 50 km."))
  assert problem(Form(..intervals_form(), cooldown: segment("", "", "5:01")))
    == Error(#("cooldown_time", "The cool-down can be at most 5 hours."))
}

pub fn rep_times_are_seconds_or_minutes_and_seconds_test() {
  assert workout_form.parse_rep_time("90") == Ok(90)
  assert workout_form.parse_rep_time("1:30") == Ok(90)
  assert workout_form.parse_rep_time("0:45") == Ok(45)
  assert workout_form.parse_rep_time("1:00:00") == Ok(3600)
  assert workout_form.parse_rep_time("1:60") == Error(Nil)
  assert workout_form.parse_rep_time("") == Error(Nil)
  assert workout_form.format_rep_time(45) == "0:45"
  assert workout_form.format_rep_time(180) == "3:00"
  assert workout_form.format_rep_time(3600) == "1:00"
}

pub fn the_parts_are_summed_up_in_words_test() {
  let one = fn(set) { plan.Intervals(plan.no_segment, [set], plan.no_segment) }
  assert workout_form.intervals_summary(
      one(plan.Set(6, work(0, 800.0, 0), work(0, 0.0, 90))),
    )
    == "6 × 800 m, 1:30 recovery"
  assert workout_form.intervals_summary(
      one(plan.Set(5, work(0, 0.0, 180), plan.no_segment)),
    )
    == "5 × 3:00"
  assert workout_form.intervals_summary(
      one(plan.Set(10, work(5, 400.0, 75), work(1, 200.0, 60))),
    )
    == "10 × 400 m in 1:15 (Zone 5), 200 m in 1:00 recovery (Zone 1)"
  assert workout_form.intervals_summary(plan.Intervals(
      work(1, 2000.0, 0),
      [
        plan.Set(3, work(0, 2000.0, 0), plan.no_segment),
        plan.Set(4, work(0, 400.0, 0), plan.no_segment),
      ],
      work(0, 0.0, 600),
    ))
    == "2 km warm-up (Zone 1) · 3 × 2 km · 4 × 400 m · 10:00 cool-down"
}

pub fn the_parts_are_written_to_steps_and_read_back_into_the_form_test() {
  let full =
    Form(
      ..intervals_form(),
      warmup: segment("1", "2", "15"),
      cooldown: segment("", "1.5", ""),
    )
  let assert Ok(valid) = workout_form.validate(full)
  let fields = workout_form.create_fields("p1", 0, valid)
  assert dict.get(fields, "steps")
    == Ok(
      "{\"v\":2,\"warmup\":{\"zone\":1,\"distance_m\":2000,\"duration_s\":900},\"sets\":[{\"reps\":6,\"work\":{\"zone\":4,\"distance_m\":800,\"duration_s\":170},\"recovery\":{\"duration_s\":90}}],\"cooldown\":{\"distance_m\":1500}}",
    )
  let stored =
    Row(
      Workout("w1", "p1", 0, 0, "Track", plan.Interval, None, None),
      "",
      valid.intervals,
      4,
      "T",
    )
  assert workout_form.from_row(stored)
    == Form(..full, title: "Track", zone: "4", sets: [
      workout_form.SetForm(
        "6",
        segment("4", "800", "2:50"),
        segment("", "", "1:30"),
      ),
    ])
  assert workout_form.steps_field(None) == outbox.field_null("steps")
}

pub fn an_edit_sends_steps_only_when_the_parts_changed_test() {
  let assert Ok(valid) = workout_form.validate(intervals_form())
  let stored =
    Row(
      Workout("w1", "p1", 0, 0, "Easy run", plan.Interval, None, None),
      "",
      valid.intervals,
      0,
      "T",
    )
  assert workout_form.changed_fields(stored, valid, 0) == dict.new()
  // Steps of the first version, read with the workout's zone in their reps: the zone goes, and the steps are
  // written again so that the reps keep it (ADR 0117).
  let first_version = Row(..stored, zone: 4)
  assert workout_form.changed_fields(first_version, valid, 0)
    == dict.from_list([
      workout_form.steps_field(valid.intervals),
      outbox.field_int("zone", 0),
    ])
  let assert Ok(fewer) =
    workout_form.validate(
      with_set(fn(set) { workout_form.SetForm(..set, reps: "5") }),
    )
  assert dict.keys(workout_form.changed_fields(stored, fewer, 0)) == ["steps"]
  let assert Ok(tempo) =
    workout_form.validate(Form(..intervals_form(), kind: plan.Run, zone: "4"))
  assert workout_form.changed_fields(stored, tempo, 0)
    == dict.from_list([
      outbox.field_string("kind", "run"),
      outbox.field_null("steps"),
      outbox.field_int("zone", 4),
    ])
}

pub fn sets_are_added_as_copies_and_removed_test() {
  let f = workout_form.add_set(intervals_form())
  let assert [first, second] = f.sets
  assert first == second
  let f = workout_form.type_reps(f, 1, "3")
  let assert [_, second] = f.sets
  assert second.reps == "3"
  let f = workout_form.remove_set(f, 0)
  assert f.sets == [second]
  assert workout_form.remove_set(f, 0).sets == [workout_form.blank_set]
}

pub fn a_zone_is_chosen_stored_and_typed_back_test() {
  let assert Ok(valid) = workout_form.validate(Form(..form(), zone: "2"))
  assert valid.zone == 2
  assert dict.get(workout_form.create_fields("p1", 0, valid), "zone") == Ok("2")
  let stored =
    Row(
      Workout("w1", "p1", 0, 0, "Easy run", plan.Run, None, None),
      "",
      None,
      2,
      "T",
    )
  assert workout_form.from_row(stored) == Form(..form(), zone: "2")
  assert workout_form.changed_fields(stored, valid, 0) == dict.new()
  let assert Ok(none) = workout_form.validate(form())
  assert dict.keys(workout_form.changed_fields(stored, none, 0)) == ["zone"]
}

pub fn a_rest_day_has_no_zone_and_a_zone_must_be_1_to_5_test() {
  let assert Ok(rest) =
    workout_form.validate(Form(..form(), kind: plan.Rest, zone: "3"))
  assert rest.zone == 0
  assert workout_form.validate_fields(Form(..form(), zone: "6"))
    == Error(#("zone", "Choose a zone from 1 to 5."))
  assert workout_form.zone_label(4) == "Zone 4"
  assert workout_form.zone_label(0) == ""
}

// WORKED OUT FROM THE ZONE (ADR 0106) --------------------------------------------------------------

/// Threshold 5:00 /km: zone 2 from 6:27 to 5:43 (planned at 6:05), zone 4 from 5:18 to 4:58 (5:08), zone 5 from 4:57.
fn zones() -> pace_zones.PaceZones {
  pace_zones.defaults(300)
}

pub fn a_zone_is_planned_at_its_middle_and_zone_5_at_its_start_test() {
  assert pace_zones.planning_pace(zones(), 2) == Ok(365)
  assert pace_zones.planning_pace(zones(), 4) == Ok(308)
  assert pace_zones.planning_pace(zones(), 5) == Ok(297)
  assert pace_zones.planning_pace(zones(), 6) == Error(Nil)
}

pub fn a_typed_distance_gives_the_duration_at_the_zone_pace_test() {
  let f =
    Form(..form(), zone: "2")
    |> workout_form.type_distance("10", zones())
  // 10 km at 6:05 is 60:50, to the nearest minute.
  assert f.duration == "1:01"
  assert f.distance_km == "10"
}

pub fn a_typed_duration_gives_the_distance_to_100_m_test() {
  let f =
    Form(..form(), zone: "2")
    |> workout_form.type_duration("45", zones())
  // 2700 s at 365 s/km is 7.397 km.
  assert f.distance_km == "7.4"
}

pub fn another_zone_works_out_again_from_what_was_typed_test() {
  let f =
    Form(..form(), zone: "2")
    |> workout_form.type_duration("45", zones())
    |> workout_form.choose_zone("4", zones())
  assert f.duration == "45"
  // 2700 s at 308 s/km is 8.766 km.
  assert f.distance_km == "8.8"
}

pub fn clearing_the_typed_value_clears_the_worked_out_one_test() {
  let f =
    Form(..form(), zone: "2")
    |> workout_form.type_distance("10", zones())
    |> workout_form.type_distance("", zones())
  assert f.duration == ""
}

pub fn nothing_is_worked_out_without_a_zone_or_before_anything_is_typed_test() {
  let f = workout_form.type_distance(form(), "10", zones())
  assert f.duration == ""
  let stored =
    workout_form.choose_zone(workout_form.from_row(row()), "4", zones())
  assert stored.distance_km == "8"
  assert stored.duration == "45"
  let rest =
    Form(..form(), kind: plan.Rest, zone: "2")
    |> workout_form.type_distance("10", zones())
  assert rest.duration == ""
}

pub fn a_rep_is_worked_out_in_seconds_and_tens_of_metres_test() {
  let f =
    Form(..form(), kind: plan.Interval)
    |> workout_form.edit_segment(
      workout_form.Work(0),
      workout_form.ZoneField,
      "4",
      zones(),
    )
    |> workout_form.edit_segment(
      workout_form.Work(0),
      workout_form.DistanceField,
      "800",
      zones(),
    )
  // 800 m at 308 s/km is 246.4 s.
  assert workout_form.segment(f, workout_form.Work(0)).time == "4:06"
  let f =
    workout_form.edit_segment(
      f,
      workout_form.Work(0),
      workout_form.TimeField,
      "90",
      zones(),
    )
  // 90 s at 308 s/km is 292 m.
  assert workout_form.segment(f, workout_form.Work(0))
    == workout_form.SegmentForm(
      "4",
      "290",
      "90",
      workout_form.TimeTyped,
      "",
      "",
    )
}

pub fn each_part_is_worked_out_at_its_own_zone_test() {
  // A recovery at zone 2: 90 s at 365 s/km is 247 m.
  let f =
    Form(..form(), kind: plan.Interval)
    |> workout_form.edit_segment(
      workout_form.Recovery(0),
      workout_form.TimeField,
      "90",
      zones(),
    )
    |> workout_form.edit_segment(
      workout_form.Recovery(0),
      workout_form.ZoneField,
      "2",
      zones(),
    )
  assert workout_form.segment(f, workout_form.Recovery(0)).distance == "250"
  // A warm-up to the minute and 100 m, like a workout: 2 km at 6:05 is 12:10.
  let f =
    workout_form.edit_segment(
      f,
      workout_form.Warmup,
      workout_form.ZoneField,
      "2",
      zones(),
    )
    |> workout_form.edit_segment(
      workout_form.Warmup,
      workout_form.DistanceField,
      "2",
      zones(),
    )
  assert workout_form.segment(f, workout_form.Warmup).time == "12"
  let f =
    workout_form.edit_segment(
      f,
      workout_form.Cooldown,
      workout_form.ZoneField,
      "2",
      zones(),
    )
    |> workout_form.edit_segment(
      workout_form.Cooldown,
      workout_form.TimeField,
      "10",
      zones(),
    )
  assert workout_form.segment(f, workout_form.Cooldown).distance == "1.6"
}

pub fn an_interval_workouts_own_targets_stay_as_typed_test() {
  let f =
    Form(..form(), kind: plan.Interval, zone: "4")
    |> workout_form.type_distance("10", zones())
  assert f.duration == ""
}

pub fn interval_totals_add_up_every_part_test() {
  assert workout_form.interval_totals(intervals_form())
    == #(Some(4800.0), Some(6 * 170 + 5 * 90))
  assert workout_form.interval_totals(
      with_set(fn(set) {
        workout_form.SetForm(..set, work: segment("", "800", ""))
      }),
    )
    == #(Some(4800.0), Some(5 * 90))
  assert workout_form.interval_totals(
      with_set(fn(set) { workout_form.SetForm(..set, reps: "x") }),
    )
    == #(None, None)
  // A warm-up, two sets with a recovery after every rep but the last, and a cool-down.
  let full =
    Form(
      ..intervals_form(),
      warmup: segment("", "2", "12"),
      sets: [
        workout_form.SetForm(
          "3",
          segment("", "1000", "4:00"),
          segment("", "200", "1:00"),
        ),
        workout_form.SetForm(
          "2",
          segment("", "400", "1:30"),
          segment("", "200", "1:00"),
        ),
      ],
      cooldown: segment("", "1", "6"),
    )
  assert workout_form.interval_totals(full)
    == #(
      Some(2000.0 +. 3000.0 +. 600.0 +. 800.0 +. 200.0 +. 1000.0),
      Some(720 + 720 + 180 + 180 + 60 + 360),
    )
}

pub fn a_day_before_the_plan_starts_cannot_be_chosen_test() {
  // The plan starts on a Wednesday (day 2): Monday and Tuesday of week 1 are not part of it.
  let starts_wednesday = Form(..form(), first_day: 2)
  assert workout_form.validate_fields(Form(..starts_wednesday, day: "2"))
    == Error(#("day", "The plan starts after this day."))
  let assert Ok(valid) =
    workout_form.validate(Form(..starts_wednesday, day: "3"))
  assert valid.day_index == 2
  let assert Ok(valid) =
    workout_form.validate(Form(..starts_wednesday, week: "2", day: "1"))
  assert valid.day_index == 7
}

// A REP AT A RACE GOAL (ADR 0118) -----------------------------------------------------------------

/// 10 km in 40:00: 4:00 /km.
fn ten_k() -> workout_form.RaceGoal {
  workout_form.RaceGoal("g1", 10_000.0, 2400)
}

fn with_goal(form: workout_form.Form) -> workout_form.Form {
  Form(..form, goals: [ten_k()])
}

fn rep(
  form: workout_form.Form,
  field: workout_form.SegmentField,
  text: String,
) {
  workout_form.edit_segment(form, workout_form.Work(0), field, text, zones())
}

pub fn a_goal_is_run_at_a_share_of_its_speed_test() {
  assert workout_form.goal_pace(ten_k(), 100) == Ok(240)
  // 240 s/km at 90 % of the speed is 266.7 s/km.
  assert workout_form.goal_pace(ten_k(), 90) == Ok(267)
  assert workout_form.goal_pace(ten_k(), 0) == Error(Nil)
  assert workout_form.goal_label(ten_k()) == "10 km in 40:00"
}

pub fn a_rep_at_a_race_goal_is_worked_out_from_its_pace_test() {
  let f =
    with_goal(Form(..form(), kind: plan.Interval))
    |> rep(workout_form.ZoneField, "4")
    |> rep(workout_form.GoalField, "g1")
    |> rep(workout_form.DistanceField, "400")
  let segment = workout_form.segment(f, workout_form.Work(0))
  // Choosing a goal clears the zone and starts at 100 %: 400 m at 4:00 /km is 1:36.
  assert segment.zone == ""
  assert segment.intensity == "100"
  assert segment.time == "1:36"
  // At 80 %, 300 s/km: 2:00.
  let f = rep(f, workout_form.IntensityField, "80")
  assert workout_form.segment(f, workout_form.Work(0)).time == "2:00"
  // A time gives the distance: 90 s at 300 s/km is 300 m.
  let f = rep(f, workout_form.TimeField, "90")
  assert workout_form.segment(f, workout_form.Work(0)).distance == "300"
  // A zone takes the goal's place.
  let f = rep(f, workout_form.ZoneField, "4")
  let segment = workout_form.segment(f, workout_form.Work(0))
  assert segment.goal == ""
  assert segment.intensity == ""
  assert segment.distance == "290"
}

pub fn a_rep_at_a_race_goal_is_saved_with_the_goal_test() {
  let f =
    with_goal(intervals_form())
    |> rep(workout_form.GoalField, "g1")
    |> rep(workout_form.IntensityField, "95")
  let assert Ok(valid) = workout_form.validate(f)
  let assert Some(plan.Intervals(sets: [set], ..)) = valid.intervals
  assert set.work
    == plan.Segment(
      0,
      800.0,
      170,
      Some(plan.GoalPace("g1", 10_000.0, 2400, 95)),
    )
  assert workout_form.steps_field(valid.intervals)
    == #(
      "steps",
      "{\"v\":2,\"sets\":[{\"reps\":6,\"work\":{\"distance_m\":800,\"duration_s\":170,\"goal\":{\"id\":\"g1\",\"distance_m\":10000,\"time_s\":2400,\"intensity\":95}},\"recovery\":{\"duration_s\":90}}]}",
    )
  let assert Some(intervals) = valid.intervals
  assert workout_form.intervals_summary(intervals)
    == "6 × 800 m in 2:50 (95 % of 10 km pace), 1:30 recovery"
}

pub fn a_race_goal_needs_an_intensity_from_1_to_100_test() {
  let f = with_goal(intervals_form()) |> rep(workout_form.GoalField, "g1")
  let with = fn(text) {
    workout_form.validate_fields(rep(f, workout_form.IntensityField, text))
  }
  let message = "Enter the intensity as a whole number from 1 to 100."
  assert with("0") == Error(#("set1_work_intensity", message))
  assert with("101") == Error(#("set1_work_intensity", message))
  assert with("") == Error(#("set1_work_intensity", message))
  let assert Ok(_) = with("1")
  // A goal that is not among the form's.
  assert workout_form.validate_fields(Form(..f, goals: []))
    == Error(#("set1_work_goal", "Choose a race goal."))
}

pub fn a_rep_keeps_a_goal_that_is_gone_and_reads_a_changed_one_anew_test() {
  let goal = Some(plan.GoalPace("g1", 10_000.0, 2400, 90))
  let stored =
    Row(
      Workout("w1", "p1", 0, 0, "Track", plan.Interval, None, None),
      "",
      Some(plan.Intervals(
        plan.no_segment,
        [plan.Set(5, plan.Segment(0, 1000.0, 267, goal), plan.no_segment)],
        plan.no_segment,
      )),
      0,
      "T",
    )
  let f = workout_form.from_row(stored)
  assert workout_form.segment(f, workout_form.Work(0)).goal == "g1"
  assert workout_form.segment(f, workout_form.Work(0)).intensity == "90"
  // Deleted since: kept as it was saved.
  assert workout_form.with_goals(f, []).goals == [ten_k()]
  // Changed since: read as it is now.
  let faster = workout_form.RaceGoal("g1", 10_000.0, 2280)
  let other = workout_form.RaceGoal("g2", 5000.0, 1200)
  assert workout_form.with_goals(f, [faster, other]).goals == [faster, other]
}
