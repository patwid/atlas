//// Sessions: the PocketBase auth token, its expiry, and what to tell the user when sign-in fails.
//// Pure. Storage and HTTP live in `storage` and `http` (ADR 0017).

import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/string

pub type Session {
  Session(token: String, user_id: String, name: String, email: String)
}

/// PocketBase tokens last 14 days by default. Refreshing when less than a week is left keeps an
/// active user signed in without a refresh on every start.
const refresh_below_seconds = 604_800

/// The `exp` claim (seconds since 1970) of a JWT, read without checking its signature. The server
/// checks signatures; the client only needs to know when to refresh.
pub fn token_expiry(token: String) -> Result(Int, Nil) {
  case string.split(token, ".") {
    [_, payload, _] ->
      case bit_array.base64_url_decode(payload) {
        Ok(bits) ->
          case bit_array.to_string(bits) {
            Ok(text) ->
              case json.parse(text, exp_decoder()) {
                Ok(exp) -> Ok(exp)
                Error(_) -> Error(Nil)
              }
            Error(Nil) -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn exp_decoder() -> decode.Decoder(Int) {
  use exp <- decode.field("exp", decode.int)
  decode.success(exp)
}

/// A token that cannot be read counts as expired.
pub fn is_expired(token: String, now_seconds: Int) -> Bool {
  case token_expiry(token) {
    Ok(exp) -> exp <= now_seconds
    Error(Nil) -> True
  }
}

pub fn should_refresh(token: String, now_seconds: Int) -> Bool {
  case token_expiry(token) {
    Ok(exp) -> exp - now_seconds < refresh_below_seconds
    Error(Nil) -> True
  }
}

/// Reads the body of a successful sign-in or refresh response.
pub fn session_from_response(body: String) -> Result(Session, Nil) {
  let decoder = {
    use token <- decode.field("token", decode.string)
    use id <- decode.subfield(["record", "id"], decode.string)
    use name <- decode.optional_field("record", "", {
      use name <- decode.optional_field("name", "", decode.string)
      decode.success(name)
    })
    use email <- decode.optional_field("record", "", {
      use email <- decode.optional_field("email", "", decode.string)
      decode.success(email)
    })
    decode.success(Session(token, id, name, email))
  }
  case json.parse(body, decoder) {
    Ok(session) if session.token != "" && session.user_id != "" -> Ok(session)
    _ -> Error(Nil)
  }
}

pub fn session_to_json(session: Session) -> String {
  json.object([
    #("token", json.string(session.token)),
    #("user_id", json.string(session.user_id)),
    #("name", json.string(session.name)),
    #("email", json.string(session.email)),
  ])
  |> json.to_string
}

pub fn session_from_json(text: String) -> Result(Session, Nil) {
  let decoder = {
    use token <- decode.field("token", decode.string)
    use user_id <- decode.field("user_id", decode.string)
    use name <- decode.field("name", decode.string)
    use email <- decode.field("email", decode.string)
    decode.success(Session(token, user_id, name, email))
  }
  case json.parse(text, decoder) {
    Ok(session) if session.token != "" && session.user_id != "" -> Ok(session)
    _ -> Error(Nil)
  }
}

/// With the refreshed token and the same user.
pub fn with_token(session: Session, token: String) -> Session {
  Session(..session, token: token)
}

/// The sign-in errors that are about what was typed, so the fields are marked (ADR 0059).
pub const missing_credentials = "Enter your e-mail and password."

pub const wrong_credentials = "Wrong e-mail or password."

/// What to show when a sign-in request failed. `status` 0 means no answer at all.
pub fn sign_in_error(status: Int, body: String) -> String {
  case status {
    0 -> "Can't reach the server. Check your connection and try again."
    400 ->
      case blank_fields(body) {
        True -> missing_credentials
        False -> wrong_credentials
      }
    429 -> "Too many attempts. Wait a minute and try again."
    _ if status >= 500 -> "The server has a problem. Try again later."
    _ -> "Sign-in failed (HTTP " <> int.to_string(status) <> ")."
  }
}

fn blank_fields(body: String) -> Bool {
  let decoder = {
    use data <- decode.field("data", decode.dict(decode.string, decode.dynamic))
    decode.success(data)
  }
  case json.parse(body, decoder) {
    Ok(data) -> dict.has_key(data, "identity") || dict.has_key(data, "password")
    Error(_) -> False
  }
}
