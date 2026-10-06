import atlas.{
  ActivitiesPage, AssignmentsPage, EmailChanged, Model, OnlineChanged,
  PasswordChanged, PlansPage, RefreshResponded, RouteChanged, SharingPage,
  SignInResponded, SignInSubmitted, SignOutClicked, SignedIn, SignedOut,
  StravaPage, WorkoutsPage,
}
import atlas/activities_page
import atlas/activity
import atlas/activity_form
import atlas/api
import atlas/assignment_form
import atlas/assignments_page
import atlas/auth.{Session}
import atlas/coaches_page
import atlas/collection
import atlas/date
import atlas/grants
import atlas/http.{Response}
import atlas/matching
import atlas/outbox
import atlas/person_finder
import atlas/plan
import atlas/plan_form
import atlas/plans_page.{Creating}
import atlas/route
import atlas/shares
import atlas/sharing_page
import atlas/signin.{Form}
import atlas/strava_page
import atlas/sync
import atlas/syncing
import atlas/today_page
import atlas/workout_form
import atlas/workouts_page
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/uri
import gleeunit
import lustre/element

pub fn main() -> Nil {
  gleeunit.main()
}

const alice = Session("old.token.x", "u1", "Alice", "alice@example.com")

fn signed_out(form: signin.Form) -> atlas.Model {
  Model(
    route.Today,
    True,
    SignedOut(form),
    syncing.new(),
    plans_page.new(),
    workouts_page.new(),
    assignments_page.new(),
    coaches_page.new(),
    activities_page.new(),
    today_page.new(),
    strava_page.new(),
    sharing_page.new(),
  )
}

fn signed_in() -> atlas.Model {
  Model(
    route.Today,
    True,
    SignedIn(alice),
    syncing.new(),
    plans_page.new(),
    workouts_page.new(),
    assignments_page.new(),
    coaches_page.new(),
    activities_page.new(),
    today_page.new(),
    strava_page.new(),
    sharing_page.new(),
  )
}

fn form_of(model: atlas.Model) -> signin.Form {
  let assert SignedOut(form) = model.auth
  form
}

const sign_in_ok =
  "{\"record\":{\"id\":\"u1\",\"name\":\"Alice\",\"email\":\"alice@example.com\"},\"token\":\"new.token.y\"}"

pub fn route_changes_update_the_model_test() {
  let assert Ok(u) = uri.parse("/plans/p1")
  let #(model, _) = atlas.update(signed_in(), RouteChanged(u))
  assert model.route == route.Plan("p1")
}

pub fn going_offline_is_reflected_test() {
  let #(model, _) = atlas.update(signed_in(), OnlineChanged(False))
  assert !model.online
  let #(model, _) = atlas.update(model, OnlineChanged(True))
  assert model.online
}

pub fn typing_fills_the_form_test() {
  let #(model, _) =
    atlas.update(signed_out(signin.empty()), EmailChanged("a@b.c"))
  let #(model, _) = atlas.update(model, PasswordChanged("secret"))
  assert form_of(model) == Form("a@b.c", "secret", False, None)
}

pub fn submitting_an_empty_form_asks_for_both_fields_test() {
  let #(model, _) =
    atlas.update(signed_out(Form("a@b.c", "", False, None)), SignInSubmitted)
  assert form_of(model).error == Some("Enter your e-mail and password.")
  assert !form_of(model).busy
}

pub fn submitting_marks_the_form_busy_and_clears_the_error_test() {
  let start = Form("a@b.c", "secret", False, Some("old error"))
  let #(model, _) = atlas.update(signed_out(start), SignInSubmitted)
  assert form_of(model) == Form("a@b.c", "secret", True, None)
}

pub fn a_second_submit_while_busy_is_ignored_test() {
  let busy = signed_out(Form("a@b.c", "secret", True, None))
  let #(model, _) = atlas.update(busy, SignInSubmitted)
  assert model == busy
}

pub fn a_successful_sign_in_starts_the_session_test() {
  let busy = signed_out(Form("alice@example.com", "secret", True, None))
  let #(model, _) =
    atlas.update(busy, SignInResponded(Response(200, sign_in_ok)))
  assert model.auth
    == SignedIn(Session("new.token.y", "u1", "Alice", "alice@example.com"))
}

pub fn a_wrong_password_keeps_the_e_mail_and_clears_the_password_test() {
  let busy = signed_out(Form("alice@example.com", "wrong", True, None))
  let body =
    "{\"data\":{},\"message\":\"Failed to authenticate.\",\"status\":400}"
  let #(model, _) = atlas.update(busy, SignInResponded(Response(400, body)))
  assert form_of(model)
    == Form("alice@example.com", "", False, Some("Wrong e-mail or password."))
}

pub fn no_connection_is_explained_test() {
  let busy = signed_out(Form("a@b.c", "secret", True, None))
  let #(model, _) = atlas.update(busy, SignInResponded(Response(0, "")))
  assert form_of(model).error
    == Some("Can't reach the server. Check your connection and try again.")
  assert !form_of(model).busy
}

pub fn a_200_without_a_usable_session_is_not_a_sign_in_test() {
  let busy = signed_out(Form("a@b.c", "secret", True, None))
  let #(model, _) =
    atlas.update(
      busy,
      SignInResponded(Response(200, "<html>captive portal</html>")),
    )
  let assert SignedOut(form) = model.auth
  assert !form.busy
  assert form.error != None
}

pub fn late_sign_in_answers_do_not_disturb_a_signed_in_user_test() {
  let #(model, _) =
    atlas.update(signed_in(), SignInResponded(Response(400, "")))
  assert model == signed_in()
  let #(model, _) = atlas.update(signed_in(), EmailChanged("x"))
  assert model == signed_in()
}

pub fn a_refresh_replaces_the_token_and_keeps_the_user_test() {
  let #(model, _) =
    atlas.update(signed_in(), RefreshResponded(Response(200, sign_in_ok)))
  assert model.auth
    == SignedIn(Session("new.token.y", "u1", "Alice", "alice@example.com"))
}

pub fn a_refresh_for_another_user_cannot_change_the_account_test() {
  let other =
    "{\"record\":{\"id\":\"u2\",\"name\":\"Mallory\",\"email\":\"m@example.com\"},\"token\":\"t.t.t\"}"
  let #(model, _) =
    atlas.update(signed_in(), RefreshResponded(Response(200, other)))
  let assert SignedIn(session) = model.auth
  assert session.user_id == "u1"
  assert session.email == "alice@example.com"
}

pub fn an_unreadable_refresh_changes_nothing_test() {
  let #(model, _) =
    atlas.update(signed_in(), RefreshResponded(Response(200, "nonsense")))
  assert model == signed_in()
}

pub fn a_rejected_token_signs_out_with_an_explanation_test() {
  let #(model, _) =
    atlas.update(signed_in(), RefreshResponded(Response(401, "")))
  assert form_of(model).error == Some("Your session expired. Sign in again.")
  assert form_of(model).email == ""
}

pub fn offline_or_server_trouble_keeps_the_session_test() {
  let #(model, _) = atlas.update(signed_in(), RefreshResponded(Response(0, "")))
  assert model == signed_in()
  let #(model, _) =
    atlas.update(signed_in(), RefreshResponded(Response(503, "")))
  assert model == signed_in()
}

pub fn signing_out_shows_an_empty_form_test() {
  let #(model, _) = atlas.update(signed_in(), SignOutClicked)
  assert model.auth == SignedOut(signin.empty())
}

pub fn signing_out_forgets_the_loaded_sync_state_test() {
  let loaded =
    Model(
      ..signed_in(),
      syncing: syncing.State(..syncing.new(), phase: syncing.Ready),
    )
  let #(model, _) = atlas.update(loaded, SignOutClicked)
  assert model.syncing.phase == syncing.NotLoaded
}

pub fn signing_in_starts_loading_the_device_data_test() {
  let busy = signed_out(Form("alice@example.com", "secret", True, None))
  let #(model, _) =
    atlas.update(busy, SignInResponded(Response(200, sign_in_ok)))
  assert model.syncing.phase == syncing.Loading
}

fn ready_syncing() -> syncing.State {
  syncing.State(
    ..syncing.new(),
    sync: option.Some(sync.new(outbox.new(), [], None)),
    phase: syncing.Ready,
  )
}

pub fn saving_a_new_plan_queues_it_for_upload_test() {
  let typing =
    Model(
      ..signed_in(),
      syncing: ready_syncing(),
      plans: plans_page.Model(
        ..plans_page.new(),
        mode: Creating,
        form: plan_form.Form("Half marathon", "", plan.Public, None),
      ),
    )
  let #(model, _) = atlas.update(typing, PlansPage(plans_page.Submitted))
  let assert option.Some(engine) = model.syncing.sync
  let assert [entry] = sync.outbox(engine).entries
  assert entry.kind == outbox.Create
  assert entry.id != ""
  assert entry.fields
    == dict.from_list([
      outbox.field_string("owner", "u1"),
      outbox.field_string("title", "Half marathon"),
      outbox.field_string("description", ""),
      outbox.field_string("visibility", "public"),
    ])
  assert model.plans.mode == plans_page.Browsing
}

pub fn an_invalid_plan_is_not_queued_test() {
  let typing =
    Model(
      ..signed_in(),
      syncing: ready_syncing(),
      plans: plans_page.Model(..plans_page.new(), mode: Creating),
    )
  let #(model, _) = atlas.update(typing, PlansPage(plans_page.Submitted))
  let assert option.Some(engine) = model.syncing.sync
  assert outbox.is_empty(sync.outbox(engine))
  assert model.plans.form.error == option.Some("Give the plan a title.")
}

pub fn signing_out_clears_the_plans_on_screen_test() {
  let showing =
    Model(
      ..signed_in(),
      plans: plans_page.Model(..plans_page.new(), plans: [
        plan.Plan("p1", "u1", "Private plan", "", plan.Private, "T"),
      ]),
    )
  let #(model, _) = atlas.update(showing, SignOutClicked)
  assert model.plans == plans_page.new()
}

fn plan_screen(owner: String) -> atlas.Model {
  Model(
    ..signed_in(),
    route: route.Plan("p1"),
    syncing: ready_syncing(),
    plans: plans_page.Model(
      ..plans_page.new(),
      plans: [plan.Plan("p1", owner, "10k plan", "", plan.Private, "T")],
      loaded: True,
    ),
    workouts: workouts_page.Model(
      ..workouts_page.new(),
      mode: workouts_page.Adding,
      form: workout_form.Form(
        "1",
        "2",
        "Easy run",
        plan.Easy,
        "8",
        "45",
        "",
        None,
      ),
    ),
  )
}

pub fn saving_a_workout_queues_it_for_upload_test() {
  let #(model, _) =
    atlas.update(plan_screen("u1"), WorkoutsPage(workouts_page.Submitted))
  let assert option.Some(engine) = model.syncing.sync
  let assert [entry] = sync.outbox(engine).entries
  assert entry.kind == outbox.Create
  assert entry.collection == collection.Workouts
  assert dict.get(entry.fields, "plan") == Ok("\"p1\"")
  assert dict.get(entry.fields, "day_index") == Ok("1")
  assert dict.get(entry.fields, "distance_m") == Ok("8000")
  assert dict.get(entry.fields, "duration_s") == Ok("2700")
}

pub fn workouts_of_someone_elses_plan_cannot_be_saved_test() {
  let #(model, _) =
    atlas.update(plan_screen("u2"), WorkoutsPage(workouts_page.Submitted))
  let assert option.Some(engine) = model.syncing.sync
  assert outbox.is_empty(sync.outbox(engine))
}

pub fn workouts_cannot_be_saved_when_no_plan_is_open_test() {
  let model = Model(..plan_screen("u1"), route: route.Plans)
  let #(next, _) = atlas.update(model, WorkoutsPage(workouts_page.Submitted))
  let assert option.Some(engine) = next.syncing.sync
  assert outbox.is_empty(sync.outbox(engine))
}

pub fn signing_out_clears_the_workouts_on_screen_too_test() {
  let showing =
    Model(
      ..plan_screen("u1"),
      workouts: workouts_page.Model(..workouts_page.new(), rows: [
        workout_form.Row(
          plan.Workout("w1", "p1", 0, 0, "Secret", plan.Easy, None, None),
          "",
          "T",
        ),
      ]),
    )
  let #(model, _) = atlas.update(showing, SignOutClicked)
  assert model.workouts == workouts_page.new()
}

fn schedule_screen(owner: String, visibility: plan.Visibility) -> atlas.Model {
  Model(
    ..signed_in(),
    route: route.Plan("p1"),
    syncing: ready_syncing(),
    plans: plans_page.Model(
      ..plans_page.new(),
      plans: [plan.Plan("p1", owner, "10k plan", "", visibility, "T")],
      loaded: True,
    ),
    coaches: coaches_page.Model(
      ..coaches_page.new(),
      grants: [grants.Grant("g1", "ana", "u1", "Ana", "Alice", "T")],
      loaded: True,
    ),
    assignments: assignments_page.Model(
      ..assignments_page.new(),
      mode: assignments_page.Starting,
      form: assignment_form.Form("u1", "2026-11-02", None),
    ),
  )
}

pub fn starting_your_own_plan_queues_an_assignment_test() {
  let #(model, _) =
    atlas.update(
      schedule_screen("u1", plan.Private),
      AssignmentsPage(assignments_page.Submitted),
    )
  let assert option.Some(engine) = model.syncing.sync
  let assert [entry] = sync.outbox(engine).entries
  assert entry.collection == collection.Assignments
  assert dict.get(entry.fields, "plan") == Ok("\"p1\"")
  assert dict.get(entry.fields, "athlete") == Ok("\"u1\"")
  assert dict.get(entry.fields, "assigned_by") == Ok("\"u1\"")
  assert dict.get(entry.fields, "start_date") == Ok("\"2026-11-02\"")
}

pub fn a_coach_can_start_the_plan_for_an_athlete_who_granted_access_test() {
  let model = schedule_screen("u1", plan.Private)
  let for_ana =
    Model(
      ..model,
      assignments: assignments_page.Model(
        ..model.assignments,
        form: assignment_form.Form("ana", "2026-11-02", None),
      ),
    )
  let #(next, _) =
    atlas.update(for_ana, AssignmentsPage(assignments_page.Submitted))
  let assert option.Some(engine) = next.syncing.sync
  let assert [entry] = sync.outbox(engine).entries
  assert dict.get(entry.fields, "athlete") == Ok("\"ana\"")
  assert dict.get(entry.fields, "assigned_by") == Ok("\"u1\"")
}

pub fn a_private_plan_of_someone_else_cannot_be_started_test() {
  // The server would refuse it (ADR 0009), so the app does not even offer it (ADR 0023).
  let #(next, _) =
    atlas.update(
      Model(
        ..schedule_screen("u2", plan.Private),
        assignments: assignments_page.new(),
      ),
      AssignmentsPage(assignments_page.StartClicked),
    )
  assert next.assignments.mode == assignments_page.Browsing
}

pub fn a_public_plan_of_someone_else_can_be_started_test() {
  let #(next, _) =
    atlas.update(
      Model(
        ..schedule_screen("u2", plan.Public),
        assignments: assignments_page.new(),
      ),
      AssignmentsPage(assignments_page.StartClicked),
    )
  assert next.assignments.mode == assignments_page.Starting
}

pub fn nothing_is_queued_without_a_plan_on_screen_test() {
  let model = Model(..schedule_screen("u1", plan.Private), route: route.Plans)
  let #(next, _) =
    atlas.update(model, AssignmentsPage(assignments_page.Submitted))
  let assert option.Some(engine) = next.syncing.sync
  assert outbox.is_empty(sync.outbox(engine))
}

pub fn signing_out_clears_the_schedule_and_the_coach_list_test() {
  let #(model, _) =
    atlas.update(schedule_screen("u1", plan.Private), SignOutClicked)
  assert model.assignments == assignments_page.new()
  assert model.coaches == coaches_page.new()
}

fn activities_screen() -> atlas.Model {
  Model(
    ..signed_in(),
    route: route.Activities,
    syncing: ready_syncing(),
    activities: activities_page.Model(
      ..activities_page.new(),
      mode: activities_page.Adding,
      form: activity_form.Form(
        "2026-10-05",
        "07:30",
        activity.Run,
        "Morning run",
        "8,5",
        "45",
        "",
        "",
        None,
      ),
    ),
  )
}

pub fn saving_a_manual_activity_queues_it_for_upload_test() {
  let #(model, _) =
    atlas.update(activities_screen(), ActivitiesPage(activities_page.Submitted))
  let assert option.Some(engine) = model.syncing.sync
  let assert [entry] = sync.outbox(engine).entries
  assert entry.kind == outbox.Create
  assert entry.collection == collection.Activities
  assert dict.get(entry.fields, "owner") == Ok("\"u1\"")
  assert dict.get(entry.fields, "source") == Ok("\"manual\"")
  assert dict.get(entry.fields, "distance_m") == Ok("8500")
  // The start is stored in UTC, whatever the time zone of the machine running the test is.
  let assert Ok(started) = dict.get(entry.fields, "started_at")
  assert string.ends_with(started, ":00.000Z\"")
}

pub fn an_invalid_activity_is_not_queued_test() {
  let invalid =
    Model(
      ..activities_screen(),
      activities: activities_page.Model(
        ..activities_page.new(),
        mode: activities_page.Adding,
        form: activity_form.Form(
          "2026-10-05",
          "07:30",
          activity.Run,
          "",
          "",
          "",
          "",
          "",
          None,
        ),
      ),
    )
  let #(model, _) =
    atlas.update(invalid, ActivitiesPage(activities_page.Submitted))
  let assert option.Some(engine) = model.syncing.sync
  assert outbox.is_empty(sync.outbox(engine))
  assert model.activities.form.error
    == option.Some("Enter a distance or a time, or both.")
}

pub fn signing_out_clears_the_activities_on_screen_test() {
  let showing =
    Model(
      ..signed_in(),
      activities: activities_page.Model(..activities_page.new(), rows: [
        activity_form.Row(
          activity.Activity(
            "x",
            activity.Manual,
            "2026-10-01 05:30:00.000Z",
            activity.Run,
            1.0,
            1,
          ),
          "u1",
          "Private run",
          0.0,
          0,
          "T",
        ),
      ]),
    )
  let #(model, _) = atlas.update(showing, SignOutClicked)
  assert model.activities == activities_page.new()
}

fn today_screen() -> atlas.Model {
  Model(
    ..signed_in(),
    route: route.Today,
    syncing: ready_syncing(),
    assignments: assignments_page.Model(..assignments_page.new(), rows: [
      assignment_form.Row(
        plan.Assignment("a1", "p1", "u1", date.Date(2020, 1, 6)),
        "u1",
        "T",
      ),
    ]),
    workouts: workouts_page.Model(..workouts_page.new(), rows: [
      workout_form.Row(
        plan.Workout("w1", "p1", 0, 0, "Easy", plan.Easy, None, None),
        "",
        "T",
      ),
    ]),
    activities: activities_page.Model(..activities_page.new(), rows: [
      activity_form.Row(
        activity.Activity(
          "x1",
          activity.Manual,
          "2020-01-06 07:00:00.000Z",
          activity.Run,
          5000.0,
          1500,
        ),
        "u1",
        "",
        0.0,
        0,
        "T",
      ),
    ]),
  )
}

pub fn the_today_screen_shows_old_schedules_as_outside_its_window_test() {
  // The plan started years ago, so nothing falls in the window around today.
  let html = element.to_string(atlas.view(today_screen()))
  assert string.contains(html, "Nothing planned for today.")
}

pub fn signing_out_clears_the_matches_on_screen_test() {
  let showing =
    Model(
      ..signed_in(),
      daily: today_page.Model(..today_page.new(), matches: [
        matching.Stored("m1", "u1", matching.Match("x", "w", "a"), False, "T"),
      ]),
    )
  let #(model, _) = atlas.update(showing, SignOutClicked)
  assert model.daily == today_page.new()
}

pub fn coming_back_from_strava_shows_the_result_test() {
  let #(model, _) =
    atlas.update(signed_in(), StravaPage(strava_page.Returned("connected")))
  assert model.strava.message
    == option.Some(strava_page.Info(
      "Strava is connected. Your last 30 days are being imported.",
    ))
  let #(model, _) =
    atlas.update(signed_in(), StravaPage(strava_page.Returned("denied")))
  assert model.strava.message
    == option.Some(strava_page.Problem("Strava access was not granted."))
}

pub fn the_strava_section_is_shown_in_settings_test() {
  let html =
    element.to_string(atlas.view(Model(..signed_in(), route: route.Settings)))
  assert string.contains(html, "Strava")
  assert string.contains(html, "Checking")
}

pub fn strava_messages_are_ignored_when_signed_out_test() {
  let model = signed_out(Form("", "", False, None))
  let #(next, _) = atlas.update(model, StravaPage(strava_page.ConnectClicked))
  assert next == model
}

pub fn signing_out_clears_the_strava_state_test() {
  let showing =
    Model(
      ..signed_in(),
      strava: strava_page.Model(
        ..strava_page.new(),
        status: strava_page.Known(api.StravaStatus(True, True)),
      ),
    )
  let #(model, _) = atlas.update(showing, SignOutClicked)
  assert model.strava == strava_page.new()
}

fn copy_screen(workouts_loaded: Bool) -> atlas.Model {
  Model(
    ..signed_in(),
    route: route.Plan("src"),
    syncing: ready_syncing(),
    plans: plans_page.Model(
      ..plans_page.new(),
      plans: [
        plan.Plan("src", "coach", "10k plan", "Build up", plan.Public, "T"),
      ],
      loaded: True,
    ),
    workouts: workouts_page.Model(
      ..workouts_page.new(),
      loaded: workouts_loaded,
      rows: [
        workout_form.Row(
          plan.Workout(
            "w2",
            "src",
            3,
            0,
            "Tempo",
            plan.Tempo,
            option.Some(8000.0),
            None,
          ),
          "",
          "T",
        ),
        workout_form.Row(
          plan.Workout("w1", "src", 0, 0, "Easy", plan.Easy, None, None),
          "",
          "T",
        ),
        workout_form.Row(
          plan.Workout(
            "other",
            "elsewhere",
            0,
            0,
            "Not mine",
            plan.Easy,
            None,
            None,
          ),
          "",
          "T",
        ),
      ],
    ),
  )
}

pub fn copying_a_plan_queues_the_plan_first_and_then_its_workouts_in_order_test() {
  let #(model, _) =
    atlas.update(copy_screen(True), PlansPage(plans_page.CopyClicked("src")))
  let assert option.Some(engine) = model.syncing.sync
  let entries = sync.outbox(engine).entries
  assert list.map(entries, fn(e) { e.collection })
    == [collection.Plans, collection.Workouts, collection.Workouts]
  let assert [plan_entry, first, second] = entries
  assert dict.get(plan_entry.fields, "title") == Ok("\"Copy of 10k plan\"")
  assert dict.get(plan_entry.fields, "owner") == Ok("\"u1\"")
  assert dict.get(plan_entry.fields, "visibility") == Ok("\"private\"")
  assert dict.get(plan_entry.fields, "source_plan") == Ok("\"src\"")
  // Both workouts belong to the new plan, in day order, and the other plan's workout is left out.
  assert dict.get(first.fields, "plan") == Ok("\"" <> plan_entry.id <> "\"")
  assert dict.get(second.fields, "plan") == Ok("\"" <> plan_entry.id <> "\"")
  assert dict.get(first.fields, "title") == Ok("\"Easy\"")
  assert dict.get(second.fields, "title") == Ok("\"Tempo\"")
  // The screen links to the copy.
  assert model.plans.copy == plans_page.Copied("src", plan_entry.id)
}

pub fn a_copy_waits_until_the_workouts_have_been_read_test() {
  let #(model, _) =
    atlas.update(copy_screen(False), PlansPage(plans_page.CopyClicked("src")))
  let assert option.Some(engine) = model.syncing.sync
  // Copying now would leave the workouts behind: nothing is queued.
  assert outbox.is_empty(sync.outbox(engine))
  let assert plans_page.CopyProblem("src", message) = model.plans.copy
  assert string.contains(message, "still loading")
}

fn sharing_screen(owner: String) -> atlas.Model {
  Model(
    ..signed_in(),
    route: route.Plan("p1"),
    syncing: ready_syncing(),
    plans: plans_page.Model(
      ..plans_page.new(),
      plans: [plan.Plan("p1", owner, "10k plan", "", plan.Private, "T")],
      loaded: True,
    ),
    sharing: sharing_page.Model(
      ..sharing_page.new(),
      finder: person_finder.Model(
        "bob@example.com",
        person_finder.Found(grants.Person("bob", "Bob")),
      ),
    ),
  )
}

pub fn sharing_your_own_plan_queues_a_share_with_names_test() {
  let #(model, _) =
    atlas.update(sharing_screen("u1"), SharingPage(sharing_page.ShareClicked))
  let assert option.Some(engine) = model.syncing.sync
  let assert [entry] = sync.outbox(engine).entries
  assert entry.collection == collection.PlanShares
  assert dict.get(entry.fields, "plan") == Ok("\"p1\"")
  assert dict.get(entry.fields, "user") == Ok("\"bob\"")
  assert dict.get(entry.fields, "user_name") == Ok("\"Bob\"")
  assert dict.get(entry.fields, "shared_by_name") == Ok("\"Alice\"")
}

pub fn a_plan_that_is_not_yours_cannot_be_shared_test() {
  let #(model, _) =
    atlas.update(
      sharing_screen("someone-else"),
      SharingPage(sharing_page.ShareClicked),
    )
  let assert option.Some(engine) = model.syncing.sync
  assert outbox.is_empty(sync.outbox(engine))
}

pub fn a_private_plan_shared_with_you_can_be_started_test() {
  let model =
    Model(
      ..schedule_screen("u2", plan.Private),
      assignments: assignments_page.new(),
      sharing: sharing_page.Model(..sharing_page.new(), shares: [
        shares.Share("s1", "p1", "u1", "Alice", "Zed", False, "T"),
      ]),
    )
  let #(next, _) =
    atlas.update(model, AssignmentsPage(assignments_page.StartClicked))
  assert next.assignments.mode == assignments_page.Starting
}

pub fn a_removed_share_no_longer_allows_starting_test() {
  let model =
    Model(
      ..schedule_screen("u2", plan.Private),
      assignments: assignments_page.new(),
      sharing: sharing_page.Model(..sharing_page.new(), shares: [
        shares.Share("s1", "p1", "u1", "Alice", "Zed", True, "T"),
      ]),
    )
  let #(next, _) =
    atlas.update(model, AssignmentsPage(assignments_page.StartClicked))
  assert next.assignments.mode == assignments_page.Browsing
}

pub fn the_plan_list_says_who_shared_a_plan_test() {
  let model =
    Model(
      ..signed_in(),
      route: route.Plans,
      plans: plans_page.Model(
        ..plans_page.new(),
        plans: [plan.Plan("p1", "zed", "Zed's plan", "", plan.Private, "T")],
        loaded: True,
      ),
      sharing: sharing_page.Model(..sharing_page.new(), shares: [
        shares.Share("s1", "p1", "u1", "Alice", "Zed", False, "T"),
      ]),
    )
  let html = element.to_string(atlas.view(model))
  assert string.contains(html, "Shared by Zed")
  let opened =
    element.to_string(atlas.view(Model(..model, route: route.Plan("p1"))))
  assert string.contains(opened, "Shared with you by Zed.")
}

pub fn only_the_owner_sees_the_sharing_section_test() {
  let owner = element.to_string(atlas.view(sharing_screen("u1")))
  assert string.contains(owner, "Share with someone by e-mail address")
  let other = element.to_string(atlas.view(sharing_screen("someone-else")))
  assert !string.contains(other, "Share with someone by e-mail address")
}

pub fn signing_out_clears_the_shares_on_screen_test() {
  let showing =
    Model(
      ..signed_in(),
      sharing: sharing_page.Model(..sharing_page.new(), shares: [
        shares.Share("s1", "p1", "u1", "Alice", "Zed", False, "T"),
      ]),
    )
  let #(model, _) = atlas.update(showing, SignOutClicked)
  assert model.sharing == sharing_page.new()
}
