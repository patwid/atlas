import atlas/assignment_form.{type Row, Row}
import atlas/assignments_page.{
  AssignmentsRead, AthleteChanged, Browsing, ChangeDateClicked, ChangingDate,
  Context, Create, DateChanged, Delete, Edit, Model, RemoveClicked,
  RemoveConfirmed, StartClicked, Starting, Submitted,
}
import atlas/date.{type Date, Date}
import atlas/grants.{Grant, Person}
import atlas/outbox
import atlas/plan.{Assignment, Workout}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element

const today = Date(2026, 10, 6)

fn context(athletes: List(grants.Person)) -> assignments_page.Context {
  Context("p1", "me", athletes, today, True)
}

fn row(id: String, athlete: String, assigned_by: String, start: Date) -> Row {
  Row(Assignment(id, "p1", athlete, start), assigned_by, "T-" <> id)
}

fn with_rows(rows: List(Row)) -> assignments_page.Model {
  Model(..assignments_page.new(), rows: rows, loaded: True)
}

fn update(
  model: assignments_page.Model,
  msg: assignments_page.Msg,
  athletes: List(grants.Person),
) {
  let #(next, _, actions) =
    assignments_page.update(model, msg, context(athletes))
  #(next, actions)
}

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

pub fn assignments_are_read_and_listed_by_start_for_the_plan_on_screen_test() {
  let stored = [
    dynamic_of(
      "{\"id\":\"b\",\"plan\":\"p1\",\"athlete\":\"me\",\"start_date\":\"2026-12-01\"}",
    ),
    dynamic_of(
      "{\"id\":\"a\",\"plan\":\"p1\",\"athlete\":\"me\",\"start_date\":\"2026-11-02\"}",
    ),
    dynamic_of(
      "{\"id\":\"x\",\"plan\":\"p2\",\"athlete\":\"me\",\"start_date\":\"2026-10-01\"}",
    ),
    dynamic_of(
      "{\"id\":\"gone\",\"plan\":\"p1\",\"athlete\":\"me\",\"start_date\":\"2026-10-01\",\"deleted\":true}",
    ),
    dynamic_of(
      "{\"id\":\"bad\",\"plan\":\"p1\",\"athlete\":\"me\",\"start_date\":\"soon\"}",
    ),
  ]
  let #(model, _) =
    update(assignments_page.new(), AssignmentsRead(Ok(stored)), [])
  assert model.loaded
  assert list.map(assignments_page.rows_of(model, "p1"), fn(r) {
      r.assignment.id
    })
    == ["a", "b"]
}

pub fn starting_a_plan_for_oneself_creates_an_assignment_test() {
  let #(model, _) = update(assignments_page.new(), StartClicked, [])
  assert model.mode == Starting
  assert model.form.athlete_id == "me"
  assert model.form.start_date == "2026-10-06"
  let #(model, _) = update(model, DateChanged("2026-11-02"), [])
  let #(model, actions) = update(model, Submitted, [])
  let assert [Create(id, fields)] = actions
  assert id != ""
  assert fields
    == dict.from_list([
      outbox.field_string("plan", "p1"),
      outbox.field_string("athlete", "me"),
      outbox.field_string("assigned_by", "me"),
      outbox.field_string("start_date", "2026-11-02"),
    ])
  assert model.mode == Browsing
}

pub fn a_coach_can_start_the_plan_for_a_granted_athlete_test() {
  let athletes = [Person("ana", "Ana")]
  let #(model, _) = update(assignments_page.new(), StartClicked, athletes)
  let #(model, _) = update(model, AthleteChanged("ana"), athletes)
  let #(_, actions) = update(model, Submitted, athletes)
  let assert [Create(_, fields)] = actions
  assert dict.get(fields, "athlete") == Ok("\"ana\"")
  assert dict.get(fields, "assigned_by") == Ok("\"me\"")
}

pub fn nobody_else_can_be_chosen_test() {
  let #(model, _) =
    update(assignments_page.new(), StartClicked, [Person("ana", "Ana")])
  let #(model, _) =
    update(model, AthleteChanged("stranger"), [Person("ana", "Ana")])
  let #(model, actions) = update(model, Submitted, [Person("ana", "Ana")])
  assert actions == []
  assert model.mode == Starting
  assert model.form.error == Some("You cannot start this plan for that person.")
}

pub fn a_bad_date_shows_an_error_and_saves_nothing_test() {
  let #(model, _) = update(assignments_page.new(), StartClicked, [])
  let #(model, _) = update(model, DateChanged(""), [])
  let #(model, actions) = update(model, Submitted, [])
  assert actions == []
  assert model.form.error == Some("Pick a start date.")
  let #(model, _) = update(model, DateChanged("2026-11-02"), [])
  assert model.form.error == None
}

pub fn changing_the_date_sends_only_the_date_with_the_local_base_test() {
  let model = with_rows([row("a", "me", "me", Date(2026, 11, 2))])
  let #(model, _) = update(model, ChangeDateClicked("a"), [])
  assert model.mode == ChangingDate("a")
  assert model.form.start_date == "2026-11-02"
  let #(model, _) = update(model, DateChanged("2026-11-09"), [])
  let #(model, actions) = update(model, Submitted, [])
  assert actions
    == [
      Edit(
        "a",
        dict.from_list([outbox.field_string("start_date", "2026-11-09")]),
        "T-a",
      ),
    ]
  assert model.mode == Browsing
}

pub fn an_unchanged_date_writes_nothing_test() {
  let model = with_rows([row("a", "me", "me", Date(2026, 11, 2))])
  let #(model, _) = update(model, ChangeDateClicked("a"), [])
  let #(_, actions) = update(model, Submitted, [])
  assert actions == []
}

pub fn a_coach_can_change_what_they_assigned_but_not_other_peoples_test() {
  let mine = row("a", "ana", "me", Date(2026, 11, 2))
  let theirs = row("b", "ana", "other-coach", Date(2026, 11, 2))
  assert assignments_page.may_change(mine, "me")
  assert !assignments_page.may_change(theirs, "me")
  let model = with_rows([theirs])
  let #(next, actions) = update(model, RemoveConfirmed("b"), [])
  assert next == model
  assert actions == []
  let #(next, _) = update(model, ChangeDateClicked("b"), [])
  assert next.mode == Browsing
}

pub fn the_athlete_can_always_change_their_own_schedule_test() {
  assert assignments_page.may_change(
    row("a", "me", "coach", Date(2026, 11, 2)),
    "me",
  )
}

pub fn removing_needs_a_second_click_test() {
  let model = with_rows([row("a", "me", "me", Date(2026, 11, 2))])
  let #(asked, actions) = update(model, RemoveClicked("a"), [])
  assert asked.confirming == Some("a")
  assert actions == []
  let #(done, actions) = update(asked, RemoveConfirmed("a"), [])
  assert actions == [Delete("a", "T-a")]
  assert done.confirming == None
}

pub fn an_assignment_removed_elsewhere_ends_its_edit_test() {
  let editing =
    Model(
      ..with_rows([row("a", "me", "me", Date(2026, 11, 2))]),
      mode: ChangingDate("a"),
    )
  let #(model, _) = update(editing, AssignmentsRead(Ok([])), [])
  assert model.mode == Browsing
}

// What is on the screen ---------------------------------------------------------------------------

fn workouts() -> List(plan.Workout) {
  [Workout("w", "p1", 27, 0, "Long", plan.Long, None, None)]
}

fn grants_list() -> List(grants.Grant) {
  [
    Grant("g1", "ana", "me", "Ana", "Me", "T"),
    Grant("g2", "me", "coach", "Me", "Coach C", "T"),
  ]
}

fn html_of(
  model: assignments_page.Model,
  athletes: List(grants.Person),
) -> String {
  element.to_string(assignments_page.view(
    model,
    context(athletes),
    workouts(),
    grants_list(),
  ))
}

pub fn a_schedule_shows_start_and_end_with_weekdays_test() {
  let html = html_of(with_rows([row("a", "me", "me", Date(2026, 11, 2))]), [])
  assert string.contains(html, "You")
  assert string.contains(html, "Starts Mon 2 Nov 2026")
  assert string.contains(html, "ends Sun 29 Nov 2026")
  assert string.contains(html, "Change date")
  assert string.contains(html, "Remove")
  assert !string.contains(html, "Assigned by")
}

pub fn an_assignment_made_by_a_coach_says_so_test() {
  let html =
    html_of(with_rows([row("a", "me", "coach", Date(2026, 11, 2))]), [])
  assert string.contains(html, "Assigned by Coach C")
}

pub fn a_coach_sees_the_athletes_by_name_test() {
  let html =
    html_of(with_rows([row("a", "ana", "me", Date(2026, 11, 2))]), [
      Person("ana", "Ana"),
    ])
  assert string.contains(html, "Ana")
  assert string.contains(html, "Start or assign")
}

pub fn someone_elses_assignment_of_a_stranger_has_no_buttons_test() {
  let html =
    html_of(with_rows([row("a", "ana", "other", Date(2026, 11, 2))]), [])
  assert string.contains(html, "Ana")
  assert !string.contains(html, "Change date")
}

pub fn an_empty_schedule_invites_starting_test() {
  let html = html_of(with_rows([]), [])
  assert string.contains(html, "Nobody is following this plan yet")
  assert string.contains(html, "Start this plan")
  assert string.contains(html_of(assignments_page.new(), []), "Loading")
}

pub fn the_start_form_offers_the_athletes_and_a_date_test() {
  let model =
    Model(
      ..with_rows([]),
      mode: Starting,
      form: assignment_form.empty_for("me", today),
    )
  let html = html_of(model, [Person("ana", "Ana")])
  assert string.contains(html, "for=\"assign-athlete\"")
  assert string.contains(html, "Myself")
  assert string.contains(html, ">Ana<")
  assert string.contains(html, "type=\"date\"")
  // The date's value is set as a DOM property (ADR 0038), not a serialized attribute,
  // so it never appears in `element.to_string`'s static markup; unlike `wa.value`, the
  // other asserts above still pass through `lustre/attribute`'s plain attributes.
  // Without athletes there is no one to choose.
  assert !string.contains(html_of(model, []), "assign-athlete")
}

pub fn changing_a_date_does_not_offer_another_athlete_test() {
  let model =
    Model(
      ..with_rows([row("a", "me", "me", Date(2026, 11, 2))]),
      mode: ChangingDate("a"),
      form: assignment_form.from_row(row("a", "me", "me", Date(2026, 11, 2))),
    )
  let html = html_of(model, [Person("ana", "Ana")])
  assert string.contains(html, "Save date")
  assert !string.contains(html, "assign-athlete")
}

pub fn a_plan_that_cannot_be_started_offers_no_way_to_start_it_test() {
  let context = Context("p1", "me", [], today, False)
  let #(model, _, actions) =
    assignments_page.update(assignments_page.new(), StartClicked, context)
  assert model.mode == Browsing
  assert actions == []
  let html =
    element.to_string(assignments_page.view(
      with_rows([]),
      context,
      workouts(),
      grants_list(),
    ))
  assert !string.contains(html, "Start this plan")
  assert string.contains(html, "Nobody is following this plan yet.")
  assert !string.contains(html, "Pick a start date")
}
