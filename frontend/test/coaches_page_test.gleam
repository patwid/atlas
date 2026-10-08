import atlas/coaches_page.{
  CancelClicked, Finder, GiveAccessClicked, Grant, LookUp, Model, RemoveClicked,
  RemoveConfirmed, Revoke,
}
import atlas/grants.{Person}
import atlas/http.{Response}
import atlas/outbox
import atlas/person_finder
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

const found_body = "{\"id\":\"bob\",\"name\":\"Bob Coach\"}"

fn searching(gs: List(grants.Grant)) -> coaches_page.Model {
  Model(
    ..with_grants(gs),
    finder: person_finder.Model("bob@example.com", person_finder.Looking),
  )
}

pub fn finding_a_coach_asks_the_server_test() {
  let typed =
    Model(
      ..with_grants([]),
      finder: person_finder.Model("bob@example.com", person_finder.Idle),
    )
  let #(model, actions) = update(typed, Finder(person_finder.FindClicked))
  assert actions == [LookUp("bob@example.com")]
  assert model.finder.lookup == person_finder.Looking
}

pub fn a_found_person_must_be_confirmed_before_access_is_given_test() {
  let #(model, actions) =
    update(
      searching([]),
      Finder(person_finder.LookupAnswered(Response(200, found_body))),
    )
  assert model.finder.lookup == person_finder.Found(Person("bob", "Bob Coach"))
  assert actions == []
}

pub fn someone_who_already_has_access_is_refused_test() {
  let #(model, _) =
    update(
      searching([given("g1", "bob", "Bob Coach")]),
      Finder(person_finder.LookupAnswered(Response(200, found_body))),
    )
  assert model.finder.lookup
    == person_finder.Failed("Bob Coach already has access.")
}

pub fn giving_access_creates_a_grant_with_both_names_test() {
  let found =
    Model(
      ..with_grants([]),
      finder: person_finder.Model(
        "bob@example.com",
        person_finder.Found(Person("bob", "Bob Coach")),
      ),
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
  assert model.finder == person_finder.new()
}

pub fn giving_access_without_a_found_person_does_nothing_test() {
  let #(model, actions) = update(with_grants([]), GiveAccessClicked)
  assert actions == []
  assert model == with_grants([])
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

pub fn cancelling_the_question_keeps_the_grant_test() {
  let model =
    Model(
      ..with_grants([given("g1", "bob", "Bob Coach")]),
      confirming: Some("g1"),
    )
  let #(next, actions) = update(model, CancelClicked)
  assert next.confirming == None
  assert actions == []
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

pub fn the_form_and_the_confirmation_use_the_coach_wording_test() {
  let found =
    Model(
      ..with_grants([]),
      finder: person_finder.Model(
        "",
        person_finder.Found(Person("bob", "Bob Coach")),
      ),
    )
  let html = html_of(found)
  assert string.contains(html, "for=\"coach-email\"")
  assert string.contains(html, "Add a coach by e-mail address")
  assert string.contains(html, "Found Bob Coach. Let them see your training?")
  assert string.contains(html, "Give access")
}

pub fn the_delete_question_has_a_way_out_test() {
  let model =
    Model(
      ..with_grants([given("g1", "bob", "Bob Coach")]),
      confirming: Some("g1"),
    )
  let html = html_of(model)
  assert string.contains(html, "Bob Coach can no longer see your training.")
  assert string.contains(html, ">Remove<")
  assert string.contains(html, ">Cancel<")
}
