//// Sends an `api.Request` with `fetch`. The browser call is in `http.ffi.mjs`.
//// The answer is the status and body text; status 0 means no answer at all.

import atlas/api.{type Request, Get, Patch, Post}
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}

pub type Response {
  Response(status: Int, body: String)
}

@external(javascript, "./http.ffi.mjs", "send")
fn do_send(
  method: String,
  url: String,
  token: String,
  body: String,
  callback: fn(Int, String) -> Nil,
) -> Nil

/// Sends right away and calls back later. For use inside other effects; most code wants `send`.
pub fn perform(
  request: Request,
  token: Option(String),
  callback: fn(Response) -> Nil,
) -> Nil {
  do_send(
    method_name(request),
    request.path,
    option.unwrap(token, ""),
    option.unwrap(request.body, ""),
    fn(status, body) { callback(Response(status, body)) },
  )
}

pub fn send(
  request: Request,
  token: Option(String),
  to_msg: fn(Response) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    perform(request, token, fn(response) { dispatch(to_msg(response)) })
  })
}

fn method_name(request: Request) -> String {
  case request.method {
    Get -> "GET"
    Post -> "POST"
    Patch -> "PATCH"
  }
}

/// A stored token as an optional request token: an empty one means none.
pub fn optional_token(token: String) -> Option(String) {
  case token {
    "" -> None
    t -> Some(t)
  }
}
