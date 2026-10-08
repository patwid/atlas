import atlas/outbox
import atlas/plan.{Workout}
import atlas/workout_form.{type Row, Form, Row}
import atlas/workouts_page.{
  AddClicked, Adding, BaseWeeksChanged, Browsing, Create, DayChanged, Delete,
  DeleteClicked, DeleteConfirmed, Edit, EditClicked, EditPlan, Editing,
  GoalChanged, IntensityChanged, IntensityCleared, IntensityInput, KindChanged,
  Model, SettingsEditClicked, SettingsSubmitted, Submitted, TitleChanged,
  Viewing, WeekChanged, WeekSelected, WorkoutSelected, WorkoutsRead,
}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
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
      plan.Easy,
      Some(8000.0),
      Some(2700),
    ),
    "",
    "T-" <> id,
  )
}

fn with_rows(rows: List(Row)) -> workouts_page.Model {
  Model(..workouts_page.new(), rows: rows, loaded: True)
}

/// Base 2 weeks, pre-competition 1, competition 1, a 40 km goal and week 2 hard.
fn the_plan() -> plan.Plan {
  plan.Plan(
    ..plan.new("p1", "u1", "10k", "", plan.Private, "T-p1"),
    phases: plan.Phases(2, 1, 1),
    weekly_distance_m: Some(40_000.0),
    week_intensity: dict.from_list([#(2, 0.8)]),
  )
}

fn update(model: workouts_page.Model, msg: workouts_page.Msg) {
  let #(next, _, actions) =
    workouts_page.update(model, msg, Some(the_plan()), True)
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
  assert model.mode == Viewing("a")
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
  assert model.mode == Viewing("a")
}

pub fn deleting_needs_a_second_click_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy")])
  let #(asked, actions) = update(model, DeleteClicked("a"))
  assert asked.confirming == Some("a")
  assert actions == []
  let #(done, actions) = update(asked, DeleteConfirmed("a"))
  assert actions == [Delete("a", "T-a")]
  assert done.confirming == None
}

pub fn nothing_can_be_changed_without_permission_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy")])
  let attempt = fn(msg) {
    let #(next, _, actions) =
      workouts_page.update(model, msg, Some(the_plan()), False)
    #(next == model, actions)
  }
  assert attempt(AddClicked(1, 1)) == #(True, [])
  assert attempt(EditClicked("a")) == #(True, [])
  assert attempt(DeleteConfirmed("a")) == #(True, [])
  assert attempt(IntensityChanged("0.3")) == #(True, [])
  assert attempt(IntensityInput("0.3")) == #(True, [])
  assert attempt(IntensityCleared) == #(True, [])
  assert attempt(SettingsEditClicked) == #(True, [])
}

pub fn only_workouts_of_the_plan_on_screen_can_be_changed_test() {
  let model = with_rows([row("x", "p2", 0, 0, "Other plan")])
  let #(edit, _) = update(model, EditClicked("x"))
  assert edit.mode == Browsing
  let #(_, actions) = update(model, DeleteConfirmed("x"))
  assert actions == []
}

pub fn a_workout_removed_elsewhere_ends_an_edit_of_it_test() {
  let editing =
    Model(..with_rows([row("a", "p1", 0, 0, "Easy")]), mode: Editing("a"))
  let #(model, _) = update(editing, WorkoutsRead(Ok([])))
  assert model.mode == Browsing
}

// What is on the screen ---------------------------------------------------------------------------

fn html_of(model: workouts_page.Model, can_edit: Bool) -> String {
  element.to_string(workouts_page.view(model, the_plan(), can_edit))
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
  assert string.contains(html, "8.00 km · 45:00")
  assert string.contains(html, "Day 7")
}

pub fn the_owner_can_add_edit_and_delete_test() {
  let model =
    Model(..with_rows([row("a", "p1", 0, 0, "Easy run")]), mode: Viewing("a"))
  let html = html_of(model, True)
  assert string.contains(html, "Add workout")
  assert string.contains(html, ">Edit<")
  assert string.contains(html, ">Delete<")
  assert string.contains(html, "Add a workout to week 1, day 1")
  assert string.contains(html, ">Edit settings<")
  assert string.contains(html, "id=\"week-intensity\"")
}

pub fn others_only_read_test() {
  let model =
    Model(..with_rows([row("a", "p1", 0, 0, "Easy run")]), mode: Viewing("a"))
  let html = html_of(model, False)
  assert string.contains(html, "Easy run")
  assert !string.contains(html, "Add workout")
  assert !string.contains(html, "Add a workout to week")
  assert !string.contains(html, ">Edit<")
  assert !string.contains(html, ">Delete<")
  assert !string.contains(html, "Edit settings")
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

pub fn the_sidebar_shows_the_selected_week_against_the_goal_test() {
  let model =
    Model(
      ..with_rows([row("a", "p1", 7, 0, "Easy"), row("b", "p1", 9, 0, "Steady")]),
      selected_week: 2,
    )
  let html = html_of(model, False)
  assert string.contains(html, "Base, week 2")
  assert string.contains(html, "16.00 km of 40.00 km (40%)")
  assert string.contains(html, ">80%<")
  assert string.contains(html, "aria-valuenow=\"40\"")
}

pub fn selecting_a_week_or_a_workout_shows_it_in_the_sidebar_test() {
  let model = with_rows([row("a", "p1", 15, 0, "Tempo")])
  let #(model, _) = update(model, WeekSelected(2))
  assert model.selected_week == 2
  let #(model, actions) = update(model, WorkoutSelected("a"))
  assert model.mode == Viewing("a")
  assert model.selected_week == 3
  assert actions == []
}

pub fn the_intensity_of_the_selected_week_is_written_when_the_slider_is_let_go_test() {
  let model = Model(..with_rows([]), selected_week: 3)
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
  let model = Model(..with_rows([]), selected_week: 2)
  let html = html_of(model, True)
  assert string.contains(html, "type=\"range\"")
  assert string.contains(html, "aria-valuetext=\"80%\"")
  assert string.contains(html, ">Clear<")
  let unset = html_of(Model(..model, selected_week: 1), True)
  assert string.contains(unset, "Not set")
  assert !string.contains(unset, ">Clear<")
  let read_only = html_of(model, False)
  assert !string.contains(read_only, "type=\"range\"")
  assert string.contains(read_only, "width:80%")
}

pub fn the_plan_settings_are_edited_in_the_sidebar_test() {
  let #(model, _) = update(with_rows([]), SettingsEditClicked)
  let assert Some(settings) = model.settings
  assert settings.base_weeks == "2"
  assert settings.goal_km == "40"
  let #(model, _) = update(model, BaseWeeksChanged("6"))
  let #(model, _) = update(model, GoalChanged("45"))
  let #(model, actions) = update(model, SettingsSubmitted)
  assert model.settings == None
  assert actions
    == [
      EditPlan(
        "p1",
        dict.from_list([
          outbox.field_int("base_weeks", 6),
          outbox.field_float("weekly_distance_m", 45_000.0),
        ]),
        "T-p1",
      ),
    ]
}

pub fn invalid_plan_settings_stay_open_with_a_message_test() {
  let #(model, _) = update(with_rows([]), SettingsEditClicked)
  let #(model, _) = update(model, BaseWeeksChanged("99"))
  let #(model, actions) = update(model, SettingsSubmitted)
  assert actions == []
  assert model.settings_error
    == Some("The base phase must be a number of weeks from 0 to 52.")
  assert string.contains(html_of(model, True), "Save settings")
}

pub fn an_empty_plan_invites_the_first_workout_test() {
  assert string.contains(html_of(with_rows([]), True), "Add the first one")
  assert string.contains(html_of(with_rows([]), False), "no workouts yet")
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
        plan.Easy,
        "",
        "",
        "",
        Some("Give the workout a title."),
      ),
    )
  let html = html_of(model, True)
  assert string.contains(html, "for=\"workout-title\"")
  assert string.contains(html, "for=\"workout-distance\"")
  assert string.contains(html, "Distance (km)")
  assert string.contains(html, "Time (minutes or h:mm)")
  assert string.contains(html, "role=\"alert\"")
  assert string.contains(html, "Give the workout a title.")
  assert string.contains(html, "Easy run")
  assert string.contains(html, "Rest day")
}

pub fn the_delete_question_has_a_way_out_test() {
  let model =
    Model(
      ..with_rows([row("a", "p1", 0, 0, "Easy run")]),
      mode: Viewing("a"),
      confirming: Some("a"),
    )
  let html = html_of(model, True)
  assert string.contains(html, "Delete this workout?")
  assert string.contains(html, "Yes, delete it")
  assert string.contains(html, "Keep it")
}

pub fn the_edit_form_opens_in_the_sidebar_test() {
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
  assert string.contains(html, "Save changes")
  assert string.contains(html, "Second")
}

pub fn the_bottom_sheet_starts_collapsed_and_its_handle_toggles_it_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy run")])
  assert !model.sheet_expanded
  let html = html_of(model, True)
  assert string.contains(html, "aria-expanded=\"false\"")
  assert string.contains(html, "aria-controls=\"calendar-sheet-content\"")
  assert string.contains(html, ">Week 1<")
  let #(open, _) = update(model, workouts_page.SheetToggled)
  assert open.sheet_expanded
  assert string.contains(html_of(open, True), "aria-expanded=\"true\"")
  let #(closed, _) = update(open, workouts_page.SheetToggled)
  assert !closed.sheet_expanded
}

pub fn picking_a_workout_pulls_the_sheet_up_and_names_it_test() {
  let model = with_rows([row("a", "p1", 0, 0, "Easy run")])
  let #(viewing, _) = update(model, workouts_page.WorkoutSelected("a"))
  assert viewing.sheet_expanded
  assert string.contains(
    html_of(viewing, True),
    "<span class=\"sheet-summary\">Easy run</span>",
  )
  let #(week, _) = update(model, workouts_page.WeekSelected(2))
  assert week.sheet_expanded
  let #(adding, _) = update(model, workouts_page.AddClicked(1, 1))
  assert adding.sheet_expanded
}
