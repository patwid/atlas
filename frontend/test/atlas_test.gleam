import atlas.{
  EmailChanged, Model, OnlineChanged, PasswordChanged, RefreshResponded,
  RouteChanged, SignInResponded, SignInSubmitted, SignOutClicked, SignedIn,
  SignedOut,
}
import atlas/auth.{Session}
import atlas/http.{Response}
import atlas/route
import atlas/signin.{Form}
import gleam/option.{None, Some}
import gleam/uri
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

const alice = Session("old.token.x", "u1", "Alice", "alice@example.com")

fn signed_out(form: signin.Form) -> atlas.Model {
  Model(route.Today, True, SignedOut(form))
}

fn signed_in() -> atlas.Model {
  Model(route.Today, True, SignedIn(alice))
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
