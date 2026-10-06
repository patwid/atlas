import atlas/coaches_page.{
  CancelClicked, EmailChanged, Failed, FindClicked, Found, GiveAccessClicked,
  Grant, Idle, LookUp, Looking, LookupAnswered, Model, RemoveClicked,
  RemoveConfirmed, Revoke,
}
import atlas/grants.{Person}
import atlas/http.{Response}
import atlas/outbox
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import lustre/element

const me = Person("me", "Alice")

fn given(id: String, coach: String, coach_name: String) -> grants.Grant {
  grants.Grant(id, "me", coach, "Alice", coach_name, "T-" <> id)
}

fn with_grants(gs: List(grants.Grant)) -> coaches_page.Model {
  Model(..coaches_page.new(), grants: gs, loaded: True)
}

fn update(model: coaches_page.Model, msg: coaches_page.Msg) {
  let #(next, _, actions) = coaches_page.update(model, msg, me)
  #(next, actions)
}

fn typed(model: coaches_page.Model, email: String) -> coaches_page.Model {
  let #(next, _) = update(model, EmailChanged(email))
  next
}

const found_body = "{\"id\":\"bob\",\"name\":\"Bob Coach\"}"

pub fn finding_someone_asks_the_server_and_waits_test() {
  let #(model, actions) =
    update(typed(with_grants([]), " bob@example.com "), FindClicked)
  assert actions == [LookUp("bob@example.com")]
  assert model.lookup == Looking
  // A second click while waiting does nothing.
  let #(again, actions) = update(model, FindClicked)
  assert actions == []
  assert again == model
}

pub fn an_incomplete_address_is_not_sent_test() {
  let #(model, actions) = update(typed(with_grants([]), ""), FindClicked)
  assert actions == []
  assert model.lookup == Failed("Enter an e-mail address.")
  let #(model, actions) = update(typed(with_grants([]), "bob"), FindClicked)
  assert actions == []
  assert model.lookup == Failed("Enter a complete e-mail address.")
}

pub fn a_found_person_must_be_confirmed_before_access_is_given_test() {
  let searching =
    Model(..typed(with_grants([]), "bob@example.com"), lookup: Looking)
  let #(model, actions) =
    update(searching, LookupAnswered(Response(200, found_body)))
  assert model.lookup == Found(Person("bob", "Bob Coach"))
  assert actions == []
}

pub fn giving_access_creates_a_grant_with_both_names_test() {
  let found =
    Model(
      ..with_grants([]),
      email: "bob@example.com",
      lookup: Found(Person("bob", "Bob Coach")),
    )
  let #(model, actions) = update(found, GiveAccessClicked)
  let assert [Grant(id, fields)] = actions
  assert id != ""
  assert fields
    == dict.from_list([
      outbox.field_string("athlete", "me"),
      outbox.field_string("coach", "bob"),
      outbox.field_string("athlete_name", "Alice"),
      outbox.field_string("coach_name", "Bob Coach"),
    ])
  assert model.lookup == Idle
  assert model.email == ""
}

pub fn giving_access_without_a_found_person_does_nothing_test() {
  let #(model, actions) = update(with_grants([]), GiveAccessClicked)
  assert actions == []
  assert model == with_grants([])
}

pub fn lookup_failures_are_explained_test() {
  let searching = Model(..with_grants([]), lookup: Looking)
  let #(model, _) =
    update(
      searching,
      LookupAnswered(Response(
        404,
        "{\"message\":\"No user with this e-mail address.\"}",
      )),
    )
  assert model.lookup == Failed("Nobody with this e-mail address uses Atlas.")
  let #(model, _) = update(searching, LookupAnswered(Response(0, "")))
  assert model.lookup
    == Failed("You are offline. Looking someone up needs a connection.")
  let #(model, _) = update(searching, LookupAnswered(Response(429, "")))
  assert model.lookup
    == Failed("Too many lookups. Wait a few minutes and try again.")
}

pub fn an_unreadable_success_is_a_failure_not_a_grant_test() {
  let searching = Model(..with_grants([]), lookup: Looking)
  let #(model, actions) =
    update(
      searching,
      LookupAnswered(Response(200, "<html>captive portal</html>")),
    )
  assert actions == []
  let assert Failed(_) = model.lookup
}

pub fn yourself_and_people_with_access_are_refused_test() {
  let searching =
    Model(..with_grants([given("g1", "bob", "Bob Coach")]), lookup: Looking)
  let #(model, _) = update(searching, LookupAnswered(Response(200, found_body)))
  assert model.lookup == Failed("Bob Coach already has access.")
  let #(model, _) =
    update(
      searching,
      LookupAnswered(Response(200, "{\"id\":\"me\",\"name\":\"Alice\"}")),
    )
  assert model.lookup == Failed("That is your own address.")
}

pub fn an_answer_for_a_search_that_was_cancelled_is_ignored_test() {
  let idle = with_grants([])
  let #(model, actions) =
    update(idle, LookupAnswered(Response(200, found_body)))
  assert model == idle
  assert actions == []
  let searching = Model(..idle, lookup: Looking)
  let #(cancelled, _) = update(searching, CancelClicked)
  let #(still, _) = update(cancelled, LookupAnswered(Response(200, found_body)))
  assert still.lookup == Idle
}

pub fn typing_again_clears_an_old_result_test() {
  let model =
    Model(
      ..with_grants([]),
      lookup: Failed("Nobody with this e-mail address uses Atlas."),
    )
  assert typed(model, "x").lookup == Idle
}

pub fn removing_access_needs_a_second_click_and_uses_the_local_base_test() {
  let model = with_grants([given("g1", "bob", "Bob Coach")])
  let #(asked, actions) = update(model, RemoveClicked("g1"))
  assert asked.confirming == Some("g1")
  assert actions == []
  let #(done, actions) = update(asked, RemoveConfirmed("g1"))
  assert actions == [Revoke("g1", "T-g1")]
  assert done.confirming == None
}

pub fn only_the_athlete_can_take_access_back_test() {
  // A grant where the user is the coach is not theirs to remove.
  let theirs = grants.Grant("g9", "ana", "me", "Ana", "Alice", "T")
  let model = with_grants([theirs])
  let #(next, actions) = update(model, RemoveConfirmed("g9"))
  assert actions == []
  assert next == model
}

fn html_of(model: coaches_page.Model) -> String {
  element.to_string(coaches_page.view(model, "me"))
}

pub fn the_list_shows_coaches_by_name_and_athletes_apart_test() {
  let html =
    html_of(
      with_grants([
        given("g1", "bob", "Bob Coach"),
        grants.Grant("g2", "ana", "me", "Ana Athlete", "Alice", "T"),
      ]),
    )
  assert string.contains(html, "Bob Coach")
  assert string.contains(html, "Remove access")
  assert string.contains(html, "Athletes you coach")
  assert string.contains(html, "Ana Athlete")
}

pub fn an_empty_list_says_nobody_can_see_the_training_test() {
  let html = html_of(with_grants([]))
  assert string.contains(html, "Nobody can see your training.")
  assert !string.contains(html, "Athletes you coach")
  assert string.contains(html_of(coaches_page.new()), "Loading")
}

pub fn the_form_and_the_confirmation_are_accessible_test() {
  let html =
    html_of(Model(..with_grants([]), lookup: Found(Person("bob", "Bob Coach"))))
  assert string.contains(html, "for=\"coach-email\"")
  assert string.contains(html, "type=\"email\"")
  assert string.contains(html, "Found Bob Coach. Let them see your training?")
  assert string.contains(html, "Give access")
  assert string.contains(html, "role=\"status\"")
  let failed =
    html_of(
      Model(
        ..with_grants([]),
        lookup: Failed("Nobody with this e-mail address uses Atlas."),
      ),
    )
  assert string.contains(failed, "role=\"alert\"")
  assert string.contains(failed, "Nobody with this e-mail address uses Atlas.")
}

pub fn the_delete_question_has_a_way_out_test() {
  let model =
    Model(
      ..with_grants([given("g1", "bob", "Bob Coach")]),
      confirming: Some("g1"),
    )
  let html = html_of(model)
  assert string.contains(html, "Stop Bob Coach from seeing your training?")
  assert string.contains(html, "Yes, remove access")
  assert string.contains(html, "Keep it")
}
