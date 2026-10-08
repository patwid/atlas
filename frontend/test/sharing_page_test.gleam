import atlas/grants.{Person}
import atlas/http.{Response}
import atlas/outbox
import atlas/person_finder
import atlas/shares.{Share}
import atlas/sharing_page.{
  CancelClicked, Context, Finder, LookUp, Model, ShareAgain, ShareClicked,
  SharesRead, Stop, StopClicked, StopConfirmed,
}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import lustre/element

const me = Person("me", "Alice")

fn context() -> sharing_page.Context {
  Context("p1", me, True)
}

fn share(
  id: String,
  user: String,
  name: String,
  deleted: Bool,
) -> shares.Share {
  Share(id, "p1", user, name, "Alice", deleted, "T-" <> id)
}

fn with_shares(items: List(shares.Share)) -> sharing_page.Model {
  Model(..sharing_page.new(), shares: items, loaded: True)
}

fn update(model: sharing_page.Model, msg: sharing_page.Msg) {
  let #(next, _, actions) = sharing_page.update(model, msg, context())
  #(next, actions)
}

fn found(person: grants.Person) -> sharing_page.Model {
  Model(
    ..with_shares([]),
    finder: person_finder.Model("x@example.com", person_finder.Found(person)),
  )
}

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

pub fn shares_are_read_with_removed_ones_test() {
  let stored = [
    dynamic_of(
      "{\"id\":\"s1\",\"plan\":\"p1\",\"user\":\"bob\",\"user_name\":\"Bob\"}",
    ),
    dynamic_of(
      "{\"id\":\"s2\",\"plan\":\"p1\",\"user\":\"carl\",\"deleted\":true}",
    ),
    dynamic_of("{\"id\":\"broken\"}"),
  ]
  let #(model, _) = update(sharing_page.new(), SharesRead(Ok(stored)))
  assert model.loaded
  assert model.shares |> list_length == 2
}

fn list_length(items: List(a)) -> Int {
  case items {
    [] -> 0
    [_, ..rest] -> 1 + list_length(rest)
  }
}

pub fn finding_someone_asks_the_server_test() {
  let typed =
    Model(
      ..with_shares([]),
      finder: person_finder.Model("bob@example.com", person_finder.Idle),
    )
  let #(model, actions) = update(typed, Finder(person_finder.FindClicked))
  assert actions == [LookUp("bob@example.com")]
  assert model.finder.lookup == person_finder.Looking
}

pub fn someone_the_plan_is_already_shared_with_is_refused_test() {
  let searching =
    Model(
      ..with_shares([share("s1", "bob", "Bob", False)]),
      finder: person_finder.Model("bob@example.com", person_finder.Looking),
    )
  let #(model, _) =
    update(
      searching,
      Finder(
        person_finder.LookupAnswered(Response(
          200,
          "{\"id\":\"bob\",\"name\":\"Bob\"}",
        )),
      ),
    )
  assert model.finder.lookup
    == person_finder.Failed("Bob already has this plan.")
}

pub fn someone_it_was_shared_with_before_and_removed_can_be_found_again_test() {
  let searching =
    Model(
      ..with_shares([share("s1", "bob", "Bob", True)]),
      finder: person_finder.Model("bob@example.com", person_finder.Looking),
    )
  let #(model, _) =
    update(
      searching,
      Finder(
        person_finder.LookupAnswered(Response(
          200,
          "{\"id\":\"bob\",\"name\":\"Bob\"}",
        )),
      ),
    )
  assert model.finder.lookup == person_finder.Found(Person("bob", "Bob"))
}

pub fn confirming_creates_a_share_with_both_names_test() {
  let #(model, actions) =
    update(found(Person("bob", "Bob Runner")), ShareClicked)
  let assert [sharing_page.Share(id, fields)] = actions
  assert id != ""
  assert fields
    == dict.from_list([
      outbox.field_string("plan", "p1"),
      outbox.field_string("user", "bob"),
      outbox.field_string("user_name", "Bob Runner"),
      outbox.field_string("shared_by_name", "Alice"),
    ])
  assert model.finder == person_finder.new()
}

pub fn sharing_again_reuses_the_removed_row_test() {
  // One row per plan and person: a new row would be refused by the server.
  let model =
    Model(..found(Person("bob", "Bob Runner")), shares: [
      share("s1", "bob", "Bob", True),
    ])
  let #(_, actions) = update(model, ShareClicked)
  assert actions
    == [
      ShareAgain(
        "s1",
        dict.from_list([
          outbox.field_bool("deleted", False),
          outbox.field_string("user_name", "Bob Runner"),
          outbox.field_string("shared_by_name", "Alice"),
        ]),
        "T-s1",
      ),
    ]
}

pub fn confirming_without_a_found_person_does_nothing_test() {
  let #(model, actions) = update(with_shares([]), ShareClicked)
  assert actions == []
  assert model == with_shares([])
}

pub fn stopping_needs_a_second_click_and_uses_the_local_base_test() {
  let model = with_shares([share("s1", "bob", "Bob", False)])
  let #(asked, actions) = update(model, StopClicked("s1"))
  assert asked.confirming == Some("s1")
  assert actions == []
  let #(done, actions) = update(asked, StopConfirmed("s1"))
  assert actions == [Stop("s1", "T-s1")]
  assert done.confirming == None
}

pub fn only_current_shares_of_this_plan_can_be_stopped_test() {
  let model =
    with_shares([
      share("gone", "bob", "Bob", True),
      Share("other-plan", "p2", "bob", "Bob", "Alice", False, "T"),
    ])
  assert update(model, StopConfirmed("gone")).1 == []
  assert update(model, StopConfirmed("other-plan")).1 == []
  assert update(model, StopConfirmed("no-such")).1 == []
}

pub fn cancelling_keeps_the_share_test() {
  let model =
    Model(
      ..with_shares([share("s1", "bob", "Bob", False)]),
      confirming: Some("s1"),
    )
  let #(next, actions) = update(model, CancelClicked)
  assert next.confirming == None
  assert actions == []
}

pub fn nobody_but_the_owner_can_change_anything_test() {
  let not_owner = Context("p1", me, False)
  let model =
    Model(..found(Person("bob", "Bob")), shares: [
      share("s1", "bob", "Bob", False),
    ])
  let attempt = fn(msg) {
    let #(next, _, actions) = sharing_page.update(model, msg, not_owner)
    #(next == model, actions)
  }
  assert attempt(ShareClicked) == #(True, [])
  assert attempt(StopClicked("s1")) == #(True, [])
  assert attempt(StopConfirmed("s1")) == #(True, [])
  assert attempt(Finder(person_finder.FindClicked)) == #(True, [])
}

fn html_of(model: sharing_page.Model) -> String {
  element.to_string(sharing_page.view(model, context()))
}

pub fn the_list_shows_who_has_the_plan_by_name_test() {
  let html =
    html_of(
      with_shares([
        share("s1", "bob", "Bob", False),
        share("s2", "carl", "Carl", False),
        share("s3", "dora", "Dora", True),
      ]),
    )
  assert string.contains(html, "Bob")
  assert string.contains(html, "Carl")
  assert !string.contains(html, "Dora")
  assert string.contains(html, "Stop sharing")
  assert string.contains(html, "read it, copy it and start it")
}

pub fn an_unshared_plan_says_so_and_loading_is_shown_first_test() {
  assert string.contains(html_of(with_shares([])), "Not shared with anyone.")
  assert string.contains(html_of(sharing_page.new()), "Loading")
}

pub fn the_form_uses_the_sharing_wording_test() {
  let html = html_of(found(Person("bob", "Bob Runner")))
  assert string.contains(html, "for=\"share-email\"")
  assert string.contains(html, "Share with someone by e-mail address")
  assert string.contains(html, "Found Bob Runner. Share this plan with them?")
  assert string.contains(html, "Share plan")
}

pub fn the_stop_question_has_a_way_out_test() {
  let model =
    Model(
      ..with_shares([share("s1", "bob", "Bob", False)]),
      confirming: Some("s1"),
    )
  let html = html_of(model)
  assert string.contains(html, "Stop sharing with Bob?")
  assert string.contains(html, ">Stop sharing<")
  assert string.contains(html, ">Cancel<")
}
