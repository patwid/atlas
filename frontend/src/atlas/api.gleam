//// The requests the client sends to PocketBase and how it reads the answers. Pure: `http` does the
//// sending. The response shapes are pinned by `backend/tests/contract.test.mjs` (ADR 0017).
////
//// PocketBase treats an invalid or expired token as *anonymous*. A list then answers 200 with no
//// items, and a write fails the rules with 400 or 404, which looks like a real rejection. So
//// 400/403/404 are never final: `classify` asks for a session check first (`after_session_check`).

import atlas/collection.{type Collection}
import atlas/cursor.{type PullPlan}
import atlas/grants.{type Person, Person}
import atlas/outbox.{type Entry}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/uri

pub type Method {
  Get
  Post
  Patch
  Delete
}

pub type Request {
  Request(method: Method, path: String, body: Option(String))
}

/// The records fetched per page when pulling.
pub const page_size = 200

pub fn sign_in(email: String, password: String) -> Request {
  let body =
    json.object([
      #("identity", json.string(email)),
      #("password", json.string(password)),
    ])
    |> json.to_string
  Request(Post, "/api/collections/users/auth-with-password", Some(body))
}

/// Exchanges a valid token for a fresh one. Answers 401 when the token is no longer valid, which
/// makes it the way to check a session.
pub fn refresh() -> Request {
  Request(Post, "/api/collections/users/auth-refresh", None)
}

// STRAVA (ADR 0012, 0027) -------------------------------------------------------------------------

pub type StravaStatus {
  StravaStatus(
    /// The server has Strava credentials.
    configured: Bool,
    connected: Bool,
  )
}

pub fn strava_status() -> Request {
  Request(Get, "/api/atlas/strava/status", None)
}

/// Asks for the address to send the browser to, to connect.
pub fn strava_connect() -> Request {
  Request(Get, "/api/atlas/strava/connect", None)
}

/// Imports the last 30 days again.
pub fn strava_sync() -> Request {
  Request(Post, "/api/atlas/strava/sync", None)
}

pub fn strava_disconnect() -> Request {
  Request(Delete, "/api/atlas/strava/connection", None)
}

pub fn parse_strava_status(body: String) -> Result(StravaStatus, Nil) {
  let decoder = {
    use configured <- decode.field("configured", decode.bool)
    use connected <- decode.field("connected", decode.bool)
    decode.success(StravaStatus(configured, connected))
  }
  case json.parse(body, decoder) {
    Ok(status) -> Ok(status)
    Error(_) -> Error(Nil)
  }
}

pub fn parse_strava_url(body: String) -> Result(String, Nil) {
  let decoder = {
    use url <- decode.field("url", decode.string)
    decode.success(url)
  }
  case json.parse(body, decoder) {
    Ok(url) if url != "" -> Ok(url)
    _ -> Error(Nil)
  }
}

/// The number in answers such as `{"imported": 12}` or `{"removed": 3}`.
pub fn parse_count(body: String, field: String) -> Result(Int, Nil) {
  let decoder = {
    use count <- decode.field(field, decode.int)
    decode.success(count)
  }
  case json.parse(body, decoder) {
    Ok(count) -> Ok(count)
    Error(_) -> Error(Nil)
  }
}

/// What to tell the user when a Strava request failed. `status` 0 means no answer.
pub fn strava_error(status: Int, body: String) -> String {
  let _ = body
  case status {
    0 -> "You are offline. Strava needs a connection."
    401 -> "Your session has ended. Sign in again."
    404 -> "Strava is not connected."
    503 -> "Strava is not set up on this server."
    _ if status >= 500 -> "Strava could not be reached. Try again later."
    _ -> "That did not work (HTTP " <> int.to_string(status) <> ")."
  }
}

/// Finds a user by exact e-mail address (ADR 0010). The answer has only their ID and name.
pub fn lookup_user(email: String) -> Request {
  Request(
    Get,
    "/api/atlas/users/lookup?email=" <> encode_component(email),
    None,
  )
}

pub fn parse_lookup(body: String) -> Result(Person, Nil) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.optional_field("name", "", decode.string)
    decode.success(Person(id, name))
  }
  case json.parse(body, decoder) {
    Ok(person) if person.id != "" -> Ok(person)
    _ -> Error(Nil)
  }
}

/// What to tell the user when a lookup did not find anyone. `status` 0 means no answer.
pub fn lookup_error(status: Int, body: String) -> String {
  let message = reason(status, body)
  case status {
    0 -> "You are offline. Looking someone up needs a connection."
    401 -> "Your session has ended. Sign in again."
    404 -> "Nobody with this e-mail address uses Atlas."
    429 -> "Too many lookups. Wait a few minutes and try again."
    400 ->
      case string.contains(message, "That is you") {
        True -> "That is your own address."
        False -> "Enter a complete e-mail address."
      }
    _ -> "The lookup failed. Try again later."
  }
}

pub fn get_record(collection: Collection, id: String) -> Request {
  Request(Get, record_path(collection, id), None)
}

/// The request that sends an outbox entry. `Error` for an update whose base is still unknown:
/// look the record's `updated` up first (`get_record`) and set it with `outbox.with_base`.
pub fn entry_request(entry: Entry) -> Result(Request, Nil) {
  case outbox.needs_base(entry) {
    True -> Error(Nil)
    False ->
      Ok(case entry.kind {
        outbox.Create ->
          Request(
            Post,
            "/api/collections/"
              <> collection.to_string(entry.collection)
              <> "/records",
            Some(outbox.request_body(entry)),
          )
        outbox.Update ->
          Request(
            Patch,
            record_path(entry.collection, entry.id),
            Some(outbox.request_body(entry)),
          )
      })
  }
}

/// One page of a pull, oldest change first, with the ID as tie breaker so paging is stable.
pub fn list_page(collection: Collection, plan: PullPlan, page: Int) -> Request {
  let filter = case cursor.filter(plan) {
    Some(f) -> "&filter=" <> encode_component(f)
    None -> ""
  }
  Request(
    Get,
    "/api/collections/"
      <> collection.to_string(collection)
      <> "/records?page="
      <> int.to_string(page)
      <> "&perPage="
      <> int.to_string(page_size)
      <> "&sort=updated,id"
      <> filter,
    None,
  )
}

/// Percent-encodes text for a URL path or query. `uri.percent_encode` leaves `+` alone, but a server
/// reads `+` in a query string as a space, so an address like `name+tag@example.com` would be altered.
fn encode_component(text: String) -> String {
  string.replace(uri.percent_encode(text), "+", "%2B")
}

fn record_path(collection: Collection, id: String) -> String {
  "/api/collections/"
  <> collection.to_string(collection)
  <> "/records/"
  <> encode_component(id)
}

// ANSWERS TO ENTRIES ------------------------------------------------------------------------------

pub type Verdict {
  Final(outbox.Response)
  /// 400, 403 or 404: only a rejection if the session is valid. Check it (`refresh()`), then call
  /// `after_session_check`.
  CheckSession(reason: String)
}

/// Reads the answer to `entry_request`. `status` 0 means the request got no answer.
pub fn classify(entry: Entry, status: Int, body: String) -> Verdict {
  case status {
    200 ->
      case saved_updated(body) {
        Ok(updated) -> Final(outbox.Saved(updated))
        // The server may have saved it, but we cannot tell the new base. Retrying is safe.
        Error(Nil) -> Final(outbox.NetworkError)
      }
    401 -> Final(outbox.Unauthorized)
    409 -> Final(outbox.Conflict)
    0 | 408 | 429 -> Final(outbox.NetworkError)
    _ if status >= 500 -> Final(outbox.NetworkError)
    400 ->
      case entry.kind, id_not_unique(body) {
        outbox.Create, True -> Final(outbox.AlreadyExists)
        _, _ -> CheckSession(reason(status, body))
      }
    403 | 404 -> CheckSession(reason(status, body))
    _ -> Final(outbox.Rejected(reason(status, body)))
  }
}

/// The final response once the session check answered. A valid session makes the rejection real.
pub fn after_session_check(
  reason: String,
  session_valid: Bool,
) -> outbox.Response {
  case session_valid {
    True -> outbox.Rejected(reason)
    False -> outbox.Unauthorized
  }
}

/// The new `updated` value in a record answer.
pub fn saved_updated(body: String) -> Result(String, Nil) {
  let decoder = {
    use updated <- decode.field("updated", decode.string)
    decode.success(updated)
  }
  case json.parse(body, decoder) {
    Ok(updated) if updated != "" -> Ok(updated)
    _ -> Error(Nil)
  }
}

/// The record in a create or update answer, to store locally as the server's version.
pub fn saved_record(body: String) -> Result(Dynamic, Nil) {
  case json.parse(body, decode.dynamic) {
    Ok(record) ->
      case record_meta(record) {
        Ok(_) -> Ok(record)
        Error(Nil) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

fn id_not_unique(body: String) -> Bool {
  let decoder = {
    use code <- decode.subfield(["data", "id", "code"], decode.string)
    decode.success(code)
  }
  case json.parse(body, decoder) {
    Ok("validation_not_unique") -> True
    _ -> False
  }
}

fn reason(status: Int, body: String) -> String {
  let decoder = {
    use message <- decode.field("message", decode.string)
    decode.success(message)
  }
  case json.parse(body, decoder) {
    Ok(message) if message != "" -> message
    _ -> "The server answered with HTTP " <> int.to_string(status) <> "."
  }
}

// PULLED PAGES ------------------------------------------------------------------------------------

pub type Page {
  Page(items: List(Dynamic), page: Int, total_pages: Int)
}

/// What every synced record has. The rest is read by the collection's own decoder.
pub type Meta {
  Meta(id: String, updated: String, deleted: Bool)
}

pub fn parse_page(body: String) -> Result(Page, Nil) {
  let decoder = {
    use items <- decode.field("items", decode.list(decode.dynamic))
    use page <- decode.field("page", decode.int)
    use total_pages <- decode.field("totalPages", decode.int)
    decode.success(Page(items, page, total_pages))
  }
  case json.parse(body, decoder) {
    Ok(page) -> Ok(page)
    Error(_) -> Error(Nil)
  }
}

pub fn has_more(page: Page) -> Bool {
  page.page < page.total_pages
}

pub fn record_meta(record: Dynamic) -> Result(Meta, Nil) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use updated <- decode.field("updated", decode.string)
    use deleted <- decode.optional_field("deleted", False, decode.bool)
    decode.success(Meta(id, updated, deleted))
  }
  case decode.run(record, decoder) {
    Ok(meta) -> Ok(meta)
    Error(_) -> Error(Nil)
  }
}

/// A convenience for tests and callers: the `updated` values of a page, for `cursor.advance`.
pub fn updated_values(page: Page) -> List(String) {
  page.items
  |> list.filter_map(fn(item) {
    case record_meta(item) {
      Ok(meta) -> Ok(meta.updated)
      Error(Nil) -> Error(Nil)
    }
  })
}
