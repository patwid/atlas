import atlas/auth.{Session}
import atlas/signin
import gleam/option.{Some}
import gleam/string
import lustre/element

// Payload: {"collectionId":"_pb_users_auth_","exp":1791707435,"id":"user123","type":"auth"}
const token =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjb2xsZWN0aW9uSWQiOiJfcGJfdXNlcnNfYXV0aF8iLCJleHAiOjE3OTE3MDc0MzUsImlkIjoidXNlcjEyMyIsInR5cGUiOiJhdXRoIn0.sig"

const exp = 1_791_707_435

pub fn reads_the_expiry_from_a_token_test() {
  assert auth.token_expiry(token) == Ok(exp)
  // A payload that is only {"exp":1000}, with no padding characters.
  assert auth.token_expiry("x.eyJleHAiOjEwMDB9.y") == Ok(1000)
}

pub fn unreadable_tokens_have_no_expiry_test() {
  assert auth.token_expiry("") == Error(Nil)
  assert auth.token_expiry("garbage") == Error(Nil)
  assert auth.token_expiry("a.b.c") == Error(Nil)
  assert auth.token_expiry("a.b") == Error(Nil)
  // Valid base64 of {"id":"x"}: no exp claim.
  assert auth.token_expiry("x.eyJpZCI6IngifQ.y") == Error(Nil)
}

pub fn expiry_test() {
  assert !auth.is_expired(token, exp - 1)
  assert auth.is_expired(token, exp)
  assert auth.is_expired(token, exp + 1)
  assert auth.is_expired("garbage", 0)
}

pub fn refresh_is_due_in_the_last_week_test() {
  let week = 604_800
  assert !auth.should_refresh(token, exp - week - 1)
  assert !auth.should_refresh(token, exp - week)
  assert auth.should_refresh(token, exp - week + 1)
  assert auth.should_refresh(token, exp - 10)
  assert auth.should_refresh(token, exp + 100)
  assert auth.should_refresh("garbage", 0)
}

const response =
  "{\"record\":{\"avatar\":\"\",\"collectionId\":\"_pb_users_auth_\",\"collectionName\":\"users\",\"created\":\"2026-10-06 08:30:34.202Z\",\"email\":\"alice@example.com\",\"emailVisibility\":false,\"id\":\"nthq4py8o5gcb9s\",\"name\":\"Alice\",\"updated\":\"2026-10-06 08:30:34.202Z\",\"verified\":false},\"token\":\"abc.def.ghi\"}"

pub fn reads_a_sign_in_response_test() {
  assert auth.session_from_response(response)
    == Ok(Session(
      "abc.def.ghi",
      "nthq4py8o5gcb9s",
      "Alice",
      "alice@example.com",
    ))
}

pub fn a_user_without_name_or_email_still_signs_in_test() {
  assert auth.session_from_response(
      "{\"token\":\"t\",\"record\":{\"id\":\"u1\"}}",
    )
    == Ok(Session("t", "u1", "", ""))
}

pub fn broken_responses_are_errors_test() {
  assert auth.session_from_response("") == Error(Nil)
  assert auth.session_from_response("{}") == Error(Nil)
  assert auth.session_from_response("{\"token\":\"t\"}") == Error(Nil)
  assert auth.session_from_response(
      "{\"token\":\"\",\"record\":{\"id\":\"u1\"}}",
    )
    == Error(Nil)
  assert auth.session_from_response(
      "{\"token\":\"t\",\"record\":{\"id\":\"\"}}",
    )
    == Error(Nil)
  assert auth.session_from_response("<html>proxy error</html>") == Error(Nil)
}

pub fn a_session_survives_storage_test() {
  let session = Session("a.b.c", "u1", "Zoë \"Z\"", "z@example.com")
  assert auth.session_from_json(auth.session_to_json(session)) == Ok(session)
  assert auth.session_from_json("") == Error(Nil)
  assert auth.session_from_json("{\"token\":\"\"}") == Error(Nil)
  assert auth.session_from_json(
      "{\"token\":\"t\",\"user_id\":\"\",\"name\":\"\",\"email\":\"\"}",
    )
    == Error(Nil)
}

pub fn a_refreshed_session_keeps_the_user_test() {
  let session = Session("old", "u1", "Alice", "a@example.com")
  assert auth.with_token(session, "new")
    == Session("new", "u1", "Alice", "a@example.com")
}

pub fn sign_in_errors_are_readable_test() {
  assert auth.sign_in_error(0, "")
    == "Can't reach the server. Check your connection and try again."
  assert auth.sign_in_error(
      400,
      "{\"data\":{},\"message\":\"Failed to authenticate.\",\"status\":400}",
    )
    == "Wrong e-mail or password."
  assert auth.sign_in_error(
      400,
      "{\"data\":{\"identity\":{\"code\":\"validation_required\",\"message\":\"Cannot be blank.\"}},\"message\":\"x\",\"status\":400}",
    )
    == "Enter your e-mail and password."
  assert auth.sign_in_error(400, "not json") == "Wrong e-mail or password."
  assert auth.sign_in_error(429, "")
    == "Too many attempts. Wait a minute and try again."
  assert auth.sign_in_error(502, "")
    == "The server has a problem. Try again later."
  assert auth.sign_in_error(418, "") == "Sign-in failed (HTTP 418)."
}

pub fn wrong_credentials_mark_the_fields_but_a_lost_connection_does_not_test() {
  let html = fn(error) {
    element.to_string(signin.view(
      signin.Form(..signin.empty(), error: Some(error)),
      fn(_) { Nil },
      fn(_) { Nil },
      Nil,
    ))
  }
  let wrong = html(auth.sign_in_error(400, "{}"))
  assert string.contains(wrong, "aria-invalid=\"true\"")
  assert string.contains(wrong, "aria-describedby=\"signin-error\"")
  assert !string.contains(html(auth.sign_in_error(0, "")), "aria-invalid")
}
