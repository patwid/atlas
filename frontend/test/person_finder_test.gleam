import atlas/grants.{Person}
import atlas/http.{Response}
import atlas/person_finder.{
  CancelClicked, EmailChanged, Failed, FindClicked, Found, Idle, LookUp, Looking,
  LookupAnswered, Model, Unreachable,
}
import gleam/option.{None, Some}
import gleam/string
import lustre/element

const me = Person("me", "Alice")

const found_body = "{\"id\":\"bob\",\"name\":\"Bob Coach\"}"

fn accept(_person: grants.Person) -> option.Option(String) {
  None
}

fn update(model: person_finder.Model, msg: person_finder.Msg) {
  person_finder.update(model, msg, me, accept)
}

fn typed(email: String) -> person_finder.Model {
  update(person_finder.new(), EmailChanged(email)).0
}

pub fn finding_someone_asks_the_server_and_waits_test() {
  let #(model, actions) = update(typed(" bob@example.com "), FindClicked)
  assert actions == [LookUp("bob@example.com")]
  assert model.lookup == Looking
  // A second click while waiting does nothing.
  let #(again, actions) = update(model, FindClicked)
  assert actions == []
  assert again == model
}

pub fn an_incomplete_address_is_not_sent_test() {
  let #(model, actions) = update(typed(""), FindClicked)
  assert actions == []
  assert model.lookup == Failed("Enter an e-mail address.")
  let #(model, actions) = update(typed("bob"), FindClicked)
  assert actions == []
  assert model.lookup == Failed("Enter a complete e-mail address.")
}

pub fn a_found_person_waits_for_confirmation_test() {
  let searching = Model("bob@example.com", Looking)
  let #(model, actions) =
    update(searching, LookupAnswered(Response(200, found_body)))
  assert model.lookup == Found(Person("bob", "Bob Coach"))
  assert person_finder.found(model) == Some(Person("bob", "Bob Coach"))
  assert actions == []
}

pub fn nobody_is_found_unless_the_lookup_succeeded_test() {
  assert person_finder.found(person_finder.new()) == None
  assert person_finder.found(Model("x", Failed("no"))) == None
  assert person_finder.found(Model("x", Looking)) == None
}

pub fn lookup_failures_are_explained_test() {
  let searching = Model("x@example.com", Looking)
  let failure = fn(status, body) {
    update(searching, LookupAnswered(Response(status, body))).0.lookup
  }
  assert failure(404, "{\"message\":\"No user with this e-mail address.\"}")
    == Failed("Nobody with this e-mail address uses Atlas.")
  assert failure(0, "")
    == Unreachable("You are offline. Looking someone up needs a connection.")
  assert failure(429, "")
    == Unreachable("Too many lookups. Wait a few minutes and try again.")
}

pub fn an_unreadable_success_is_a_failure_not_a_person_test() {
  let #(model, actions) =
    update(
      Model("x@example.com", Looking),
      LookupAnswered(Response(200, "<html>captive portal</html>")),
    )
  assert actions == []
  let assert Unreachable(_) = model.lookup
}

pub fn yourself_is_refused_test() {
  let #(model, _) =
    update(
      Model("me@example.com", Looking),
      LookupAnswered(Response(200, "{\"id\":\"me\",\"name\":\"Alice\"}")),
    )
  assert model.lookup == Failed("That is your own address.")
}

pub fn the_screen_can_refuse_a_person_with_its_own_reason_test() {
  let refuse = fn(person: grants.Person) {
    case person.id {
      "bob" -> Some(person_finder.display(person) <> " already has access.")
      _ -> None
    }
  }
  let searching = Model("bob@example.com", Looking)
  let #(refused, _) =
    person_finder.update(
      searching,
      LookupAnswered(Response(200, found_body)),
      me,
      refuse,
    )
  assert refused.lookup == Failed("Bob Coach already has access.")
  let #(accepted, _) =
    person_finder.update(
      searching,
      LookupAnswered(Response(200, "{\"id\":\"carl\",\"name\":\"Carl\"}")),
      me,
      refuse,
    )
  assert accepted.lookup == Found(Person("carl", "Carl"))
}

pub fn an_answer_for_a_cancelled_search_is_ignored_test() {
  let idle = person_finder.new()
  let #(model, actions) =
    update(idle, LookupAnswered(Response(200, found_body)))
  assert model == idle
  assert actions == []
  let #(cancelled, _) = update(Model("x@example.com", Looking), CancelClicked)
  assert cancelled.lookup == Idle
  let #(still, _) = update(cancelled, LookupAnswered(Response(200, found_body)))
  assert still.lookup == Idle
}

pub fn typing_again_clears_an_old_result_test() {
  let model = Model("x", Failed("Nobody with this e-mail address uses Atlas."))
  assert update(model, EmailChanged("xy")).0 == Model("xy", Idle)
}

pub fn reset_clears_everything_test() {
  assert person_finder.reset(Model(
      "bob@example.com",
      Found(Person("bob", "Bob")),
    ))
    == person_finder.new()
}

pub fn an_unnamed_person_is_still_readable_test() {
  assert person_finder.display(Person("x", "  ")) == "This person"
  assert person_finder.display(Person("x", "Bob")) == "Bob"
}

fn labels() -> person_finder.Labels {
  person_finder.Labels(
    field_id: "the-email",
    form_class: "the-form",
    field_label: "Who?",
    field_help: "Their address",
    question: fn(name) { "Found " <> name <> ". Sure?" },
    confirm_label: "Yes please",
  )
}

fn html_of(model: person_finder.Model) -> String {
  element.to_string(person_finder.view(
    model,
    labels(),
    fn(msg) { msg },
    CancelClicked,
  ))
}

pub fn the_form_is_labelled_and_uses_the_screens_wording_test() {
  let html = html_of(Model("", Found(Person("bob", "Bob Coach"))))
  assert string.contains(html, "for=\"the-email\"")
  assert string.contains(html, "id=\"the-email\"")
  assert string.contains(html, "class=\"the-form\"")
  assert string.contains(html, "type=\"email\"")
  assert string.contains(html, "Who?")
  // The search is the field's own icon button, named for screen readers; the help shows until there is an error.
  assert string.contains(html, "aria-label=\"Find\"")
  assert string.contains(html, "Their address")
  assert string.contains(html, "Found Bob Coach. Sure?")
  assert string.contains(html, "Yes please")
  assert string.contains(html, "role=\"status\"")
}

pub fn failures_are_announced_and_looking_disables_the_button_test() {
  let failed =
    html_of(Model("", Failed("Nobody with this e-mail address uses Atlas.")))
  assert string.contains(failed, "role=\"alert\"")
  assert string.contains(failed, "Nobody with this e-mail address uses Atlas.")
  // About the address: under the field, which is marked. A lost connection is not about it.
  assert string.contains(failed, "aria-invalid=\"true\"")
  assert !string.contains(failed, "Their address")
  let offline = html_of(Model("a@b.c", Unreachable("You are offline.")))
  assert string.contains(offline, "role=\"alert\"")
  assert !string.contains(offline, "aria-invalid")
  let looking = html_of(Model("a@b.c", Looking))
  assert string.contains(looking, "Looking…")
  assert string.contains(looking, "disabled")
  assert !string.contains(html_of(Model("", Idle)), "disabled")
}
