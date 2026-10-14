import atlas/date.{Date}
import atlas/outbox
import atlas/pace_zones
import atlas/plan.{Workout}
import atlas/workout_form.{type Row, Form, Row}
import atlas/workouts_page.{
  AddClicked, Adding, Browsing, Create, DayChanged, Delete, DeleteClicked,
  DeleteExpired, Edit, EditClicked, EditPlan, Editing, IntensityChanged,
  IntensityCleared, IntensityInput, KindChanged, Model, RepsChanged,
  SegmentChanged, SetAdded, SetRemoved, Submitted, TitleChanged, Viewing,
  WeekChanged, WeekSelected, WorkoutSelected, WorkoutsRead,
}
import field_html
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn row(
  id: String,
  plan_id: String,
  day: Int,
  position: Int,
  title: String,
) -> Row {
  Row(
    Workout(
      id,
      plan_id,
      day,
      position,
      title,
      plan.Run,
      Some(8000.0),
      Some(2700),
    ),
    "",
    None,
    0,
    "T-" <> id,
  )
}

fn with_rows(rows: List(Row)) -> workouts_page.Model {
  Model(..workouts_page.new(), rows: rows, loaded: True)
}

/// Base 2 weeks, pre-competition 1, competition 1, a 40 km goal and week 2 hard.
/// The default pace zones: threshold 5:00 /km, zone 4 from 5:18 to 4:58, planned at 5:08.
fn zones() -> pace_zones.PaceZones {
  pace_zones.defaults(pace_zones.default_threshold_s)
}

fn the_plan() -> plan.Plan {
  plan.Plan(
    ..plan.new("p1", "u1", "10k", "", "T-p1"),
    phases: plan.Phases(2, 1, 1),
    weekly_distance_m: Some(40_000.0),
    week_intensity: dict.from_list([#(2, 0.8)]),
  )
}

fn update(model: workouts_page.Model, msg: workouts_page.Msg) {
  let #(next, _, actions) =
    workouts_page.update(
      model,
      msg,
      Some(the_plan()),
      True,
      zones(),
      zones(),
      [],
    )
  #(next, actions)
}

pub fn the_stored_workouts_are_read_without_deleted_or_unreadable_ones_test() {
  let stored = [
    dynamic_of(
      "{\"id\":\"a\",\"plan\":\"p1\",\"title\":\"Easy\",\"kind\":\"easy\"}",
    ),
    dynamic_of(
      "{\"id\":\"gone\",\"plan\":\"p1\",\"title\":\"x\",\"kind\":\"easy\",\"deleted\":true}",
    ),
    dynamic_of(
      "{\"id\":\"odd\",\"plan\":\"p1\",\"title\":\"x\",\"kind\":\"yoga\"}",
    ),
    dynamic_of(
      "{\"id\":\"other\",\"plan\":\"p2\",\"title\":\"y\",\"kind\":\"long\"}",
    ),
  ]
  let #(model, _) = update(workouts_page.new(), WorkoutsRead(Ok(stored)))
  assert model.loaded
  assert list.length(model.rows) == 2
  assert list.map(workouts_page.rows_of(model, "p1"), fn(r) { r.workout.id })
    == ["a"]
}

pub fn adding_starts_on_the_chosen_day_test() {
  let #(model, _) = update(workouts_page.new(), AddClicked(3, 5))
  assert model.mode == Adding
  assert model.form.week == "3"
  assert model.form.day == "5"
}

pub fn adding_a_workout_creates_it_at_the_end_of_its_day_test() {
  let model =
    with_rows([row("a", "p1", 8, 0, "First"), row("b", "p1", 8, 1, "Second")])
  let #(model, _) = update(model, AddClicked(2, 2))
  let #(model, _) = update(model, TitleChanged("Third"))
  let #(model, actions) = update(model, Submitted)
  let assert [Create(id, fields)] = actions
  assert id != ""
  assert dict.get(fields, "plan") == Ok("\"p1\"")
  assert dict.get(fields, "day_index") == Ok("8")
  assert dict.get(fields, "position") == Ok("2")
  assert dict.get(fields, "title") == Ok("\"Third\"")
  assert model.mode == Browsing
}

pub fn an_interval_workout_asks_for_its_parts_test() {
  let #(model, _) = update(workouts_page.new(), AddClicked(1, 1))
  let #(model, _) = update(model, TitleChanged("Track"))
  assert !string.contains(html_of(model, True), "Repetitions")
  let #(model, _) = update(model, KindChanged("interval"))
  let html = html_of(model, True)
  assert string.contains(html, "Repetitions")
  assert string.contains(html, "Warm-up")
  assert string.contains(html, "Cool-down")
  // Each part has its own zone, so the workout's is not asked for (ADR 0116).
  assert !string.contains(html, "id=\"workout-zone\"")
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Warmup, workout_form.TimeField, "15"),
    )
  let #(model, _) = update(model, RepsChanged(0, "6"))
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Work(0), workout_form.DistanceField, "800"),
    )
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Work(0), workout_form.ZoneField, "4"),
    )
  let #(model, _) =
    update(
      model,
      SegmentChanged(
        workout_form.Recovery(0),
        workout_form.DistanceField,
        "200",
      ),
    )
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Recovery(0), workout_form.TimeField, "1:30"),
    )
  let #(_, actions) = update(model, Submitted)
  let assert [Create(_, fields)] = actions
  assert dict.get(fields, "steps")
    == Ok(
      "{\"v\":2,\"warmup\":{\"duration_s\":900},\"sets\":[{\"reps\":6,\"work\":{\"zone\":4,\"distance_m\":800,\"duration_s\":246},\"recovery\":{\"distance_m\":200,\"duration_s\":90}}]}",
    )
  // The workout has no zone of its own (ADR 0117).
  assert dict.get(fields, "zone") == Ok("0")
}

pub fn a_race_asks_for_a_warm_up_and_cool_down_test() {
  let #(model, _) = update(workouts_page.new(), AddClicked(1, 1))
  let #(model, _) = update(model, TitleChanged("10 km"))
  let #(model, _) = update(model, KindChanged("race"))
  let html = html_of(model, True)
  assert string.contains(html, "Warm-up")
  assert string.contains(html, "Cool-down")
  assert !string.contains(html, "Repetitions")
  // The race keeps its own zone (ADR 0119).
  assert string.contains(html, "id=\"workout-zone\"")
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Warmup, workout_form.TimeField, "20"),
    )
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Cooldown, workout_form.DistanceField, "2"),
    )
  let #(_, actions) = update(model, Submitted)
  let assert [Create(_, fields)] = actions
  assert dict.get(fields, "steps")
    == Ok(
      "{\"v\":2,\"warmup\":{\"duration_s\":1200},\"cooldown\":{\"distance_m\":2000}}",
    )
}

pub fn sets_are_added_and_removed_test() {
  let #(model, _) = update(workouts_page.new(), AddClicked(1, 1))
  let #(model, _) = update(model, KindChanged("interval"))
  assert !string.contains(html_of(model, True), "Remove set")
  let #(model, _) = update(model, RepsChanged(0, "4"))
  let #(model, _) = update(model, SetAdded)
  // A new set is a copy of the last one.
  let assert [first, second] = model.form.sets
  assert second == first
  let html = html_of(model, True)
  assert string.contains(html, "Set 2")
  assert string.contains(html, "id=\"workout-set2-reps\"")
  let #(model, _) = update(model, RepsChanged(1, "3"))
  let #(model, _) = update(model, SetRemoved(0))
  let assert [only] = model.form.sets
  assert only.reps == "3"
  // The last set is emptied, not removed.
  let #(model, _) = update(model, SetRemoved(0))
  assert model.form.sets == [workout_form.blank_set]
}

pub fn a_rep_time_and_the_totals_are_worked_out_from_the_zone_test() {
  let #(model, _) = update(workouts_page.new(), AddClicked(1, 1))
  let #(model, _) = update(model, TitleChanged("Track"))
  let #(model, _) = update(model, KindChanged("interval"))
  assert !string.contains(html_of(model, True), "Total distance")
  let #(model, _) = update(model, RepsChanged(0, "6"))
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Work(0), workout_form.DistanceField, "800"),
    )
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Recovery(0), workout_form.TimeField, "1:30"),
    )
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Work(0), workout_form.ZoneField, "4"),
    )
  // 800 m at 5:08 /km, the middle of the default zone 4.
  let assert [set] = model.form.sets
  assert set.work.time == "4:06"
  let html = html_of(model, True)
  assert string.contains(html, "Total distance")
  assert string.contains(html, "value=\"4.8\"")
  // 6 × 4:06 and 5 × 1:30.
  assert string.contains(html, "value=\"32:06\"")
}

pub fn the_calendar_shows_the_parts_test() {
  let track =
    Row(
      ..row("a", "p1", 0, 0, "Track"),
      intervals: Some(plan.Intervals(
        plan.Segment(1, 2000.0, 0, None),
        [
          plan.Set(
            6,
            plan.Segment(4, 800.0, 0, None),
            plan.Segment(0, 0.0, 90, None),
          ),
        ],
        plan.no_segment,
      )),
      zone: 4,
    )
  let html = html_of(with_rows([track]), True)
  assert string.contains(
    html,
    "2 km warm-up (Zone 1) · 6 × 800 m (Zone 4), 1:30 recovery",
  )
  assert !string.contains(html, "Zone 4 · ")
}

pub fn the_calendar_shows_a_race_between_its_warm_up_and_cool_down_test() {
  let base = row("a", "p1", 0, 0, "10 km")
  let race =
    Row(
      ..base,
      workout: Workout(
        ..base.workout,
        kind: plan.Race,
        distance_m: Some(10_000.0),
        duration_s: None,
      ),
      intervals: Some(plan.Intervals(
        plan.Segment(1, 0.0, 1200, None),
        [],
        plan.Segment(0, 2000.0, 0, None),
      )),
      zone: 5,
    )
  let html = html_of(with_rows([race]), True)
  assert string.contains(html, "20:00 warm-up (Zone 1) · Zone 5 · 10")
  assert string.contains(html, "km · 2 km cool-down")
}

pub fn workouts_of_other_plans_do_not_affect_the_position_test() {
  let model = with_rows([row("x", "p2", 0, 4, "Elsewhere")])
  let #(model, _) = update(model, AddClicked(1, 1))
  let #(model, _) = update(model, TitleChanged("Mine"))
  let #(_, actions) = update(model, Submitted)
  let assert [Create(_, fields)] = actions
  assert dict.get(fields, "position") == Ok("0")
}

pub fn an_invalid_form_shows_its_error_and_saves_nothing_test() {
  let #(model, _) = update(workouts_page.new(), AddClicked(1, 1))
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.mode == Adding
  assert model.form.error == Some("Give the workout a title.")
  let #(model, _) = update(model, WeekChanged("0"))
  let #(model, _) = update(model, TitleChanged("x"))
  assert model.form.error == None
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.form.error == Some("The week must be between 1 and 60.")
}

pub fn editing_sends_only_what_changed_with_the_local_base_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy")])
  let #(model, _) = update(model, EditClicked("a"))
  assert model.mode == Editing("a")
  assert model.form.title == "Easy"
  let #(model, _) = update(model, TitleChanged("Easy run"))
  let #(model, actions) = update(model, Submitted)
  assert actions
    == [
      Edit(
        "a",
        dict.from_list([outbox.field_string("title", "Easy run")]),
        "T-a",
      ),
    ]
  assert model.mode == Browsing
}

pub fn moving_a_workout_to_another_day_is_an_edit_with_a_new_position_test() {
  let model =
    with_rows([row("a", "p1", 0, 0, "Easy"), row("b", "p1", 2, 0, "Other")])
  let #(model, _) = update(model, EditClicked("a"))
  let #(model, _) = update(model, DayChanged("3"))
  let #(_, actions) = update(model, Submitted)
  let assert [Edit("a", fields, "T-a")] = actions
  assert dict.get(fields, "day_index") == Ok("2")
  assert dict.get(fields, "position") == Ok("1")
}

pub fn the_kind_comes_from_the_select_and_unknown_values_are_ignored_test() {
  let #(model, _) = update(workouts_page.new(), KindChanged("interval"))
  assert model.form.kind == plan.Interval
  let #(model, _) = update(model, KindChanged("juggling"))
  assert model.form.kind == plan.Interval
}

pub fn an_edit_without_changes_writes_nothing_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy")])
  let #(model, _) = update(model, EditClicked("a"))
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.mode == Browsing
}

pub fn a_delete_waits_for_undo_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy")])
  let #(waiting, actions) = update(model, DeleteClicked("a"))
  assert actions == []
  let html = html_of(waiting, True)
  assert string.contains(html, "Workout deleted")
  let #(undone, _) = update(waiting, workouts_page.UndoClicked)
  let #(_, actions) = update(undone, DeleteExpired(1))
  assert actions == []
  let #(_, actions) = update(waiting, DeleteExpired(1))
  assert actions == [Delete("a", "T-a")]
}

pub fn nothing_can_be_changed_without_permission_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy")])
  let attempt = fn(msg) {
    let #(next, _, actions) =
      workouts_page.update(
        model,
        msg,
        Some(the_plan()),
        False,
        zones(),
        zones(),
        [],
      )
    #(next == model, actions)
  }
  assert attempt(AddClicked(1, 1)) == #(True, [])
  assert attempt(EditClicked("a")) == #(True, [])
  assert attempt(DeleteClicked("a")) == #(True, [])
  assert attempt(IntensityChanged("0.3")) == #(True, [])
  assert attempt(IntensityInput("0.3")) == #(True, [])
  assert attempt(IntensityCleared) == #(True, [])
}

pub fn only_workouts_of_the_plan_on_screen_can_be_changed_test() {
  let model = with_rows([row("x", "p2", 0, 0, "Other plan")])
  let #(edit, _) = update(model, EditClicked("x"))
  assert edit.mode == Browsing
  let #(next, _) = update(model, DeleteClicked("x"))
  assert next.undo == model.undo
}

pub fn a_workout_removed_elsewhere_ends_an_edit_of_it_test() {
  let editing =
    Model(..with_rows([row("a", "p1", 0, 0, "Easy")]), mode: Editing("a"))
  let #(model, _) = update(editing, WorkoutsRead(Ok([])))
  assert model.mode == Browsing
}

// What is on the screen ---------------------------------------------------------------------------

fn html_of(model: workouts_page.Model, can_edit: Bool) -> String {
  element.to_string(workouts_page.view(
    model,
    the_plan(),
    can_edit,
    Date(2026, 10, 14),
  ))
}

pub fn weeks_days_and_totals_are_shown_test() {
  let html =
    html_of(
      with_rows([
        row("a", "p1", 0, 0, "Easy run"),
        row("b", "p1", 9, 0, "Long one"),
      ]),
      True,
    )
  assert string.contains(html, "Week 1")
  assert string.contains(html, "Week 2")
  assert string.contains(html, "Easy run")
  assert string.contains(html, "Long one")
  assert string.contains(html, "8 km · 45:00")
  // Without a start date the days have their weekdays only.
  assert string.contains(html, ">Sun<")
  assert !string.contains(html, "Day 7")
}

pub fn the_owner_can_add_edit_and_delete_test() {
  let model =
    Model(
      ..with_rows([row("a", "p1", 0, 0, "Easy run")]),
      mode: Editing("a"),
      week_open: True,
    )
  let html = html_of(model, True)
  assert string.contains(
    html_of(Model(..model, mode: Browsing), True),
    "Add workout",
  )
  assert string.contains(html, "Edit workout")
  assert string.contains(html, "aria-label=\"Delete workout\"")
  assert string.contains(html, "Add a workout to week 1, Mon")
  assert string.contains(html, "id=\"week-intensity\"")
}

pub fn others_only_read_test() {
  let model =
    Model(
      ..with_rows([row("a", "p1", 0, 0, "Easy run")]),
      mode: Viewing("a"),
      week_open: True,
    )
  let html = html_of(model, False)
  assert string.contains(html, "Easy run")
  assert !string.contains(html, "Add workout")
  assert !string.contains(html, "Add a workout to week")
  assert !string.contains(html, ">Edit<")
  assert !string.contains(html, ">Delete<")
  assert !string.contains(html, "id=\"week-intensity\"")
}

pub fn the_calendar_shows_every_phase_week_with_its_intensity_test() {
  let html = html_of(with_rows([row("a", "p1", 0, 0, "Easy run")]), True)
  assert string.contains(html, "Base phase")
  assert string.contains(html, "Pre-competition phase")
  assert string.contains(html, "Competition phase")
  assert string.contains(html, "Week 4")
  assert !string.contains(html, "Week 5")
  assert string.contains(html, "intensity-high")
  assert string.contains(html, ">80%<")
}

pub fn the_week_dialog_shows_the_week_against_its_goal_test() {
  let model =
    Model(
      ..with_rows([row("a", "p1", 7, 0, "Easy"), row("b", "p1", 9, 0, "Steady")]),
      selected_week: 2,
      week_open: True,
    )
  let html = html_of(model, False)
  assert string.contains(html, "Week 2 · Base 2")
  // Week 2 is at 80%, so its goal is 80% of 40 km (ADR 0064).
  assert string.contains(html, "16 km of 32 km (50%)")
  assert string.contains(html, ">80%<")
  assert string.contains(html, "aria-valuenow=\"50\"")
}

pub fn a_week_over_its_goal_keeps_its_meter_in_range_test() {
  let rows =
    list.map([7, 8, 9, 10, 11], fn(day) {
      row("w" <> int.to_string(day), "p1", day, 0, "Easy")
    })
  let model = Model(..with_rows(rows), selected_week: 2, week_open: True)
  let html = html_of(model, False)
  assert string.contains(html, "40 km of 32 km (125%)")
  assert string.contains(html, "aria-valuenow=\"125\"")
  assert string.contains(html, "aria-valuemax=\"125\"")
}

pub fn selecting_a_week_or_a_workout_opens_its_dialog_test() {
  let model = with_rows([row("a", "p1", 15, 0, "Tempo")])
  let #(model, _) = update(model, WeekSelected(2))
  assert model.selected_week == 2
  assert model.week_open
  let #(model, _) = update(model, workouts_page.WeekClosed)
  assert !model.week_open
  let #(model, _, actions) =
    workouts_page.update(
      model,
      WorkoutSelected("a"),
      Some(the_plan()),
      False,
      zones(),
      zones(),
      [],
    )
  assert model.mode == Viewing("a")
  assert model.selected_week == 3
  assert actions == []
}

pub fn the_intensity_of_the_selected_week_is_written_when_the_slider_is_let_go_test() {
  let model = Model(..with_rows([]), selected_week: 3, week_open: True)
  let #(dragging, actions) = update(model, IntensityInput("0.35"))
  assert actions == []
  assert dragging.intensity_draft == Some(#(3, 0.35))
  assert string.contains(html_of(dragging, True), ">35%<")
  let #(done, actions) = update(dragging, IntensityChanged("0.35"))
  assert done.intensity_draft == None
  assert actions
    == [
      EditPlan(
        "p1",
        dict.from_list([#("week_intensity", "[null,0.8,0.35]")]),
        "T-p1",
      ),
    ]
  let week_two = Model(..model, selected_week: 2)
  let #(_, actions) = update(week_two, IntensityCleared)
  assert actions
    == [EditPlan("p1", dict.from_list([#("week_intensity", "[]")]), "T-p1")]
  let #(_, actions) = update(week_two, IntensityChanged("0.8"))
  assert actions == []
  let #(_, actions) = update(week_two, IntensityChanged("hard"))
  assert actions == []
}

pub fn the_slider_shows_the_week_and_others_see_a_bar_test() {
  let model = Model(..with_rows([]), selected_week: 2, week_open: True)
  let html = html_of(model, True)
  assert string.contains(html, "type=\"range\"")
  assert string.contains(html, "aria-valuetext=\"80%\"")
  assert string.contains(html, ">Clear intensity<")
  let unset = html_of(Model(..model, selected_week: 1), True)
  assert string.contains(unset, "Not set")
  assert !string.contains(unset, ">Clear intensity<")
  let read_only = html_of(model, False)
  assert !string.contains(read_only, "type=\"range\"")
  assert string.contains(read_only, "width:80%")
  assert !string.contains(read_only, ">Clear intensity<")
}

pub fn a_workout_says_its_kind_week_and_day_test() {
  let html = html_of(with_rows([row("a", "p1", 8, 0, "Shake-out")]), False)
  assert string.contains(html, "<span class=\"workout-kind\">Run</span>")
  assert string.contains(
    html,
    "aria-label=\"Shake-out, Run, week 2, Tue, 8 km · 45:00\"",
  )
}

pub fn an_empty_plan_invites_the_first_workout_test() {
  assert string.contains(html_of(with_rows([]), True), "Add the first one")
  assert string.contains(html_of(with_rows([]), False), "No workouts yet")
  assert string.contains(html_of(workouts_page.new(), True), "Loading")
}

pub fn the_form_is_labelled_and_shows_errors_test() {
  let model =
    Model(
      ..with_rows([]),
      mode: Adding,
      form: Form(
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
        workout_form.NeitherTyped,
        0,
        [],
        Some("Give the workout a title."),
      ),
    )
  let html = html_of(model, True)
  assert field_html.labelled(html, "workout-title", "Title")
  assert field_html.labelled(html, "workout-distance", "Distance")
  assert string.contains(html, ">km<")
  assert string.contains(html, "Minutes, or hours and minutes")
  // The error is under the field it is about, which is marked (ADR 0059).
  assert string.contains(html, "aria-invalid=\"true\"")
  assert string.contains(
    html,
    "class=\"field-help\" id=\"workout-title-help\" role=\"alert\">Give the workout a title.",
  )
  assert string.contains(html, ">Run<")
  assert string.contains(html, "Rest day")
  assert !string.contains(html, "Tempo run")
}

pub fn the_edit_form_opens_in_a_dialog_over_the_calendar_test() {
  let model =
    Model(
      ..with_rows([
        row("a", "p1", 0, 0, "Easy run"),
        row("b", "p1", 0, 1, "Second"),
      ]),
      mode: Editing("a"),
      form: workout_form.from_row(row("a", "p1", 0, 0, "Easy run")),
    )
  let html = html_of(model, True)
  assert string.contains(html, "data-open=\"true\"")
  assert string.contains(html, "Edit workout")
  assert string.contains(html, "Second")
  assert !string.contains(
    html_of(Model(..model, mode: workouts_page.Browsing), True),
    "Edit workout",
  )
}

pub fn a_weeks_row_shows_its_distance_against_its_goal_test() {
  let html =
    html_of(
      with_rows([row("a", "p1", 7, 0, "Easy"), row("b", "p1", 9, 0, "Steady")]),
      False,
    )
  // Week 2 is at 80% of a 40 km goal (ADR 0064, 0066).
  assert string.contains(html, "16 / 32 km")
  assert string.contains(html, "aria-haspopup=\"dialog\"")
  // Closed, the dialogs are there for opening, but empty.
  assert string.contains(html, "id=\"week-dialog\"")
  assert !string.contains(html, "id=\"week-intensity\"")
}

pub fn a_workouts_dialog_closes_only_its_own_viewing_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy run")])
  let #(viewing, _, _) =
    workouts_page.update(
      model,
      WorkoutSelected("a"),
      Some(the_plan()),
      False,
      zones(),
      zones(),
      [],
    )
  assert string.contains(
    html_of(viewing, False),
    "id=\"workout-dialog-headline\"",
  )
  // Only for reading: no Edit or Delete in it.
  assert !string.contains(html_of(viewing, False), ">Delete<")
  let #(closed, _) = update(viewing, workouts_page.WorkoutClosed)
  assert closed.mode == Browsing
  // The workout's dialog closing, when it is not open, must not end an edit.
  let #(editing, _) = update(model, EditClicked("a"))
  let #(still, _) = update(editing, workouts_page.WorkoutClosed)
  assert still.mode == Editing("a")
}

pub fn the_owner_opens_a_workout_in_its_form_with_delete_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy run")])
  let #(editing, _) = update(model, WorkoutSelected("a"))
  assert editing.mode == Editing("a")
  assert editing.form.title == "Easy run"
  let html = html_of(editing, True)
  assert string.contains(html, "aria-label=\"Delete workout\"")
  assert !string.contains(html, "id=\"workout-dialog-headline\"")
  // Cancelling goes back to the calendar.
  let #(back, _) = update(editing, workouts_page.CancelClicked)
  assert back.mode == Browsing
}

/// The plan, starting on Wednesday 4 Nov 2026.
fn dated_plan() -> plan.Plan {
  plan.Plan(..the_plan(), start_date: Some(Date(2026, 11, 4)))
}

fn update_dated(model: workouts_page.Model, msg: workouts_page.Msg) {
  let #(next, _, actions) =
    workouts_page.update(
      model,
      msg,
      Some(dated_plan()),
      True,
      zones(),
      zones(),
      [],
    )
  #(next, actions)
}

pub fn today_is_marked_on_a_dated_plan_test() {
  let html =
    element.to_string(workouts_page.view(
      with_rows([row("a", "p1", 9, 0, "Shake-out")]),
      dated_plan(),
      True,
      Date(2026, 11, 11),
    ))
  // Only today's cell is marked, for screen readers too (ADR 0129).
  assert string.contains(
    html,
    "<div aria-current=\"date\" class=\"calendar-day today \"><span class=\"day-name\"><span class=\"day-weekday\">Wed</span><span class=\"day-date\">11<",
  )
  assert list.length(string.split(html, "aria-current=\"date\"")) == 2
  let undated =
    element.to_string(workouts_page.view(
      with_rows([row("a", "p1", 9, 0, "Shake-out")]),
      the_plan(),
      True,
      Date(2026, 11, 11),
    ))
  assert !string.contains(undated, "aria-current=\"date\"")
}

pub fn a_dated_plan_shows_its_days_and_weeks_with_dates_test() {
  let html =
    element.to_string(workouts_page.view(
      with_rows([row("a", "p1", 9, 0, "Shake-out")]),
      dated_plan(),
      True,
      Date(2026, 10, 14),
    ))
  assert string.contains(html, "2–8 Nov")
  assert string.contains(html, "9–15 Nov")
  assert string.contains(html, "4 Nov")
  // The weeks are counted from the plan's start (ADR 0126).
  assert string.contains(html, "<strong>Week 1</strong>")
  assert string.contains(html, "week 2, Wed 11 Nov")
  // Monday and Tuesday of week 1 come before the start: dimmed, and nothing can be added there.
  assert string.contains(html, "calendar-day before-start")
  assert !string.contains(html, "Add a workout to week 1, Mon 2 Nov")
  assert !string.contains(html, "Add a workout to week 1, Tue 3 Nov")
  assert string.contains(html, "Add a workout to week 1, Wed 4 Nov")
}

pub fn a_workout_cannot_be_put_before_the_plan_starts_test() {
  let #(model, _) = update_dated(with_rows([]), AddClicked(1, 3))
  let #(model, _) = update_dated(model, TitleChanged("Easy"))
  let #(model, _) = update_dated(model, DayChanged("1"))
  let #(model, actions) = update_dated(model, Submitted)
  assert actions == []
  assert model.form.error == Some("The plan starts after this day.")
  let #(model, _) = update_dated(model, DayChanged("3"))
  let #(_, actions) = update_dated(model, Submitted)
  let assert [Create(_, fields)] = actions
  assert dict.get(fields, "day_index") == Ok("2")
}

pub fn add_workout_starts_on_the_plans_first_day_test() {
  let assert Some(main) =
    workouts_page.main_action(with_rows([]), dated_plan(), True)
  assert main.msg == AddClicked(1, 3)
}

pub fn a_rep_can_be_run_at_a_race_goal_of_the_athlete_test() {
  let goals = [workout_form.RaceGoal("g1", 10_000.0, 2400)]
  let #(model, _, _) =
    workouts_page.update(
      workouts_page.new(),
      AddClicked(1, 1),
      Some(the_plan()),
      True,
      zones(),
      zones(),
      goals,
    )
  let #(model, _) = update(model, KindChanged("interval"))
  // A rep is run at a zone unless chosen otherwise (ADR 0120).
  let html = html_of(model, True)
  assert string.contains(html, "name=\"set1_work_target\"")
  assert string.contains(html, ">Race goal<")
  assert string.contains(html, "id=\"workout-set1-work-zone\"")
  assert !string.contains(html, "id=\"workout-set1-work-goal\"")
  assert !string.contains(html, "id=\"workout-set1-work-intensity\"")
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Work(0), workout_form.TargetField, "goal"),
    )
  let #(model, _) =
    update(
      model,
      SegmentChanged(workout_form.Work(0), workout_form.DistanceField, "400"),
    )
  let html = html_of(model, True)
  assert string.contains(html, "id=\"workout-set1-work-goal\"")
  assert string.contains(html, "10 km in 40:00")
  assert !string.contains(html, "id=\"workout-set1-work-zone\"")
  // The intensity is a slider, at 100 % to start with.
  assert string.contains(html, "id=\"workout-set1-work-intensity\"")
  assert string.contains(html, "type=\"range\"")
  assert string.contains(html, "100 %")
  // 400 m at the goal's 4:00 /km.
  assert string.contains(html, "value=\"1:36\"")
  // Without goals, a rep is not asked what it is run at.
  let #(model, _) = update(workouts_page.new(), AddClicked(1, 1))
  let #(model, _) = update(model, KindChanged("interval"))
  assert !string.contains(html_of(model, True), "set1_work_target")
}

pub fn a_workout_but_a_rest_day_can_be_exported_to_a_watch_test() {
  let rest =
    Row(
      ..row("r", "p1", 1, 0, "Off"),
      workout: Workout(..row("r", "p1", 1, 0, "Off").workout, kind: plan.Rest),
    )
  let model = with_rows([row("a", "p1", 0, 0, "Easy run"), rest])
  // In the dialog of those who see the plan, and in the bar of the owner's form (ADR 0122).
  assert string.contains(
    html_of(Model(..model, mode: Viewing("a")), False),
    "Export to watch",
  )
  assert string.contains(
    html_of(Model(..model, mode: Editing("a")), True),
    "aria-label=\"Export to watch\"",
  )
  assert !string.contains(
    html_of(Model(..model, mode: Viewing("r")), False),
    "Export to watch",
  )
  assert !string.contains(
    html_of(Model(..model, mode: Editing("r")), True),
    "Export to watch",
  )
  // Exporting changes nothing and writes nothing.
  let #(next, actions) = update(model, workouts_page.ExportClicked("a"))
  assert next == model
  assert actions == []
}

pub fn a_workout_shows_its_distance_for_the_phone_test() {
  let html = html_of(with_rows([row("a", "p1", 8, 0, "Shake-out")]), False)
  assert string.contains(
    html,
    "<span aria-hidden=\"true\" class=\"workout-distance\">8 km</span>",
  )
}

pub fn an_interval_workout_without_a_distance_totals_its_parts_test() {
  let base = row("a", "p1", 8, 0, "Track")
  let intervals =
    plan.Intervals(
      plan.Segment(1, 2000.0, 0, None),
      [
        plan.Set(
          3,
          plan.Segment(4, 800.0, 0, None),
          plan.Segment(1, 200.0, 0, None),
        ),
        plan.Set(0, plan.no_segment, plan.no_segment),
      ],
      plan.Segment(1, 1000.0, 0, None),
    )
  let no_distance =
    Row(
      ..base,
      workout: Workout(..base.workout, kind: plan.Interval, distance_m: None),
      intervals: Some(intervals),
    )
  // 2 km + 3 × 800 m + 2 × 200 m + 1 km: no recovery after the last rep.
  assert workouts_page.total_distance(no_distance) == Some(5800.0)
  assert workouts_page.total_distance(Row(..no_distance, intervals: None))
    == None
  assert workouts_page.total_distance(base) == Some(8000.0)
}

pub fn an_interval_workouts_parts_count_towards_its_weeks_goal_test() {
  let base = row("b", "p1", 9, 0, "Track")
  let intervals =
    plan.Intervals(
      plan.Segment(1, 2000.0, 600, None),
      [
        plan.Set(
          5,
          plan.Segment(4, 1000.0, 240, None),
          plan.Segment(1, 0.0, 120, None),
        ),
      ],
      plan.Segment(1, 1000.0, 300, None),
    )
  let track =
    Row(
      ..base,
      workout: Workout(
        ..base.workout,
        kind: plan.Interval,
        distance_m: None,
        duration_s: None,
      ),
      intervals: Some(intervals),
      zone: 0,
    )
  let html = html_of(with_rows([row("a", "p1", 7, 0, "Easy"), track]), False)
  // 8 km + 2 km + 5 × 1 km + 1 km against 80% of a 40 km goal (ADR 0130).
  assert string.contains(html, "16 / 32 km")
}

pub fn an_interval_workout_asks_for_no_distance_or_duration_of_its_own_test() {
  let form =
    workout_form.Form(
      ..workout_form.empty_for(1, 1),
      kind: plan.Interval,
      sets: [
        workout_form.SetForm(
          "6",
          workout_form.SegmentForm(
            "4",
            "800",
            "",
            workout_form.NeitherTyped,
            "",
            "",
          ),
          workout_form.blank_segment,
        ),
      ],
    )
  let html = html_of(Model(..with_rows([]), mode: Adding, form: form), True)
  // Only the read-only totals of its parts (ADR 0130).
  assert !string.contains(html, "id=\"workout-distance\"")
  assert !string.contains(html, "id=\"workout-duration\"")
  assert string.contains(html, "id=\"workout-total-distance\"")
}
