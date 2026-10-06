import atlas/api.{
  CheckSession, Delete, Final, Get, Meta, Page, Patch, Post, Request,
}
import atlas/collection.{Plans, Workouts}
import atlas/cursor
import atlas/grants
import atlas/outbox
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option.{None, Some}

fn title(value: String) -> outbox.Fields {
  dict.from_list([outbox.field_string("title", value)])
}

fn first_entry(ob: outbox.Outbox) -> outbox.Entry {
  let assert [entry, ..] = ob.entries
  entry
}

pub fn sign_in_and_refresh_requests_test() {
  assert api.sign_in("a@example.com", "p\"w")
    == Request(
      Post,
      "/api/collections/users/auth-with-password",
      Some("{\"identity\":\"a@example.com\",\"password\":\"p\\\"w\"}"),
    )
  assert api.refresh()
    == Request(Post, "/api/collections/users/auth-refresh", None)
}

pub fn a_create_is_a_post_to_the_collection_test() {
  let entry =
    first_entry(outbox.record_create(outbox.new(), Plans, "p1", title("A")))
  assert api.entry_request(entry)
    == Ok(Request(
      Post,
      "/api/collections/plans/records",
      Some("{\"id\":\"p1\",\"title\":\"A\"}"),
    ))
}

pub fn an_update_is_a_patch_with_its_base_test() {
  let entry =
    first_entry(outbox.record_update(
      outbox.new(),
      Workouts,
      "w 1",
      title("A"),
      "T1",
    ))
  assert api.entry_request(entry)
    == Ok(Request(
      Patch,
      "/api/collections/workouts/records/w%201",
      Some("{\"base_updated\":\"T1\",\"title\":\"A\"}"),
    ))
}

pub fn an_update_with_an_unknown_base_cannot_be_sent_yet_test() {
  let ob =
    outbox.new()
    |> outbox.record_create(Plans, "p1", title("A"))
    |> outbox.mark_sending(1)
    |> outbox.record_update(Plans, "p1", title("B"), "x")
  let assert Ok(queued) = list.last(ob.entries)
  assert api.entry_request(queued) == Error(Nil)
  assert api.get_record(Plans, "p1")
    == Request(Get, "/api/collections/plans/records/p1", None)
}

pub fn pull_requests_page_by_updated_with_the_cursor_filter_test() {
  assert api.list_page(Plans, cursor.FullResync, 1)
    == Request(
      Get,
      "/api/collections/plans/records?page=1&perPage=200&sort=updated,id",
      None,
    )
  assert api.list_page(Workouts, cursor.Since("2026-10-05 08:00:00.000Z"), 3)
    == Request(
      Get,
      "/api/collections/workouts/records?page=3&perPage=200&sort=updated,id&filter=updated%20%3E%3D%20%222026-10-05%2008%3A00%3A00.000Z%22",
      None,
    )
}

const created =
  "{\"collectionId\":\"pbc_1\",\"deleted\":false,\"id\":\"p1\",\"title\":\"t\",\"updated\":\"2026-10-06 08:30:35.585Z\"}"

fn classify(
  kind_entry: outbox.Entry,
  status: Int,
  body: String,
) -> api.Verdict {
  api.classify(kind_entry, status, body)
}

fn create_entry() -> outbox.Entry {
  first_entry(outbox.record_create(outbox.new(), Plans, "p1", title("A")))
}

fn update_entry() -> outbox.Entry {
  first_entry(outbox.record_update(outbox.new(), Plans, "p1", title("A"), "T1"))
}

pub fn success_carries_the_new_updated_value_test() {
  assert classify(create_entry(), 200, created)
    == Final(outbox.Saved("2026-10-06 08:30:35.585Z"))
  assert classify(update_entry(), 200, created)
    == Final(outbox.Saved("2026-10-06 08:30:35.585Z"))
}

pub fn an_unreadable_success_is_retried_not_trusted_test() {
  assert classify(create_entry(), 200, "") == Final(outbox.NetworkError)
  assert classify(create_entry(), 200, "{}") == Final(outbox.NetworkError)
  assert classify(create_entry(), 200, "<html>captive portal</html>")
    == Final(outbox.NetworkError)
}

pub fn no_answer_and_server_trouble_are_retried_test() {
  assert classify(create_entry(), 0, "") == Final(outbox.NetworkError)
  assert classify(create_entry(), 500, "") == Final(outbox.NetworkError)
  assert classify(create_entry(), 503, "") == Final(outbox.NetworkError)
  assert classify(create_entry(), 429, "") == Final(outbox.NetworkError)
  assert classify(create_entry(), 408, "") == Final(outbox.NetworkError)
}

pub fn unauthorized_and_conflict_test() {
  assert classify(update_entry(), 401, "") == Final(outbox.Unauthorized)
  assert classify(
      update_entry(),
      409,
      "{\"message\":\"The record was changed since base_updated.\"}",
    )
    == Final(outbox.Conflict)
}

const duplicate_id =
  "{\"data\":{\"id\":{\"code\":\"validation_not_unique\",\"message\":\"Value must be unique.\"}},\"message\":\"Failed to create record.\",\"status\":400}"

pub fn a_duplicate_id_on_create_means_an_earlier_attempt_took_effect_test() {
  assert classify(create_entry(), 400, duplicate_id)
    == Final(outbox.AlreadyExists)
  // The same body on an update is not a replay.
  assert classify(update_entry(), 400, duplicate_id)
    == CheckSession("Failed to create record.")
}

pub fn other_rejections_need_a_session_check_before_they_are_final_test() {
  assert classify(
      create_entry(),
      400,
      "{\"data\":{\"visibility\":{\"code\":\"validation_invalid_value\"}},\"message\":\"Failed to create record.\",\"status\":400}",
    )
    == CheckSession("Failed to create record.")
  assert classify(
      update_entry(),
      400,
      "{\"message\":\"Base_updated is required when updating this collection.\"}",
    )
    == CheckSession("Base_updated is required when updating this collection.")
  assert classify(
      update_entry(),
      404,
      "{\"message\":\"The requested resource wasn't found.\"}",
    )
    == CheckSession("The requested resource wasn't found.")
  assert classify(update_entry(), 403, "")
    == CheckSession("The server answered with HTTP 403.")
}

pub fn the_session_check_decides_between_rejected_and_sign_in_test() {
  assert api.after_session_check("nope", True) == outbox.Rejected("nope")
  assert api.after_session_check("nope", False) == outbox.Unauthorized
}

pub fn other_client_errors_are_final_rejections_test() {
  assert classify(create_entry(), 413, "{\"message\":\"Too large.\"}")
    == Final(outbox.Rejected("Too large."))
}

const page_body =
  "{\"items\":[{\"id\":\"a\",\"updated\":\"2026-10-05 09:00:00.000Z\",\"deleted\":false,\"title\":\"x\"},{\"id\":\"b\",\"updated\":\"2026-10-05 10:00:00.000Z\",\"deleted\":true},{\"id\":\"c\",\"updated\":\"2026-10-05 11:00:00.000Z\"}],\"page\":1,\"perPage\":200,\"totalItems\":450,\"totalPages\":3}"

pub fn pages_are_read_with_their_records_test() {
  let assert Ok(page) = api.parse_page(page_body)
  assert page.page == 1
  assert page.total_pages == 3
  assert list.length(page.items) == 3
  assert api.has_more(page)
  assert api.updated_values(page)
    == [
      "2026-10-05 09:00:00.000Z",
      "2026-10-05 10:00:00.000Z",
      "2026-10-05 11:00:00.000Z",
    ]
}

pub fn record_metadata_defaults_deleted_to_false_test() {
  let assert Ok(Page(items, _, _)) = api.parse_page(page_body)
  let metas = list.filter_map(items, api.record_meta)
  assert metas
    == [
      Meta("a", "2026-10-05 09:00:00.000Z", False),
      Meta("b", "2026-10-05 10:00:00.000Z", True),
      Meta("c", "2026-10-05 11:00:00.000Z", False),
    ]
}

pub fn the_last_page_has_no_more_test() {
  let assert Ok(page) =
    api.parse_page(
      "{\"items\":[],\"page\":3,\"perPage\":200,\"totalItems\":450,\"totalPages\":3}",
    )
  assert !api.has_more(page)
  let assert Ok(empty) =
    api.parse_page(
      "{\"items\":[],\"page\":1,\"perPage\":200,\"totalItems\":0,\"totalPages\":0}",
    )
  assert !api.has_more(empty)
}

pub fn broken_pages_and_records_are_errors_test() {
  assert api.parse_page("") == Error(Nil)
  assert api.parse_page("{\"items\":5}") == Error(Nil)
  assert api.parse_page("{\"items\":[]}") == Error(Nil)
  assert api.record_meta(dynamic.int(5)) == Error(Nil)
}

pub fn the_lookup_request_encodes_the_address_test() {
  assert api.lookup_user("a+b@example.com")
    == Request(Get, "/api/atlas/users/lookup?email=a%2Bb%40example.com", None)
}

pub fn a_lookup_answer_gives_the_person_test() {
  assert api.parse_lookup("{\"id\":\"u2\",\"name\":\"Bob\"}")
    == Ok(grants.Person("u2", "Bob"))
  assert api.parse_lookup("{\"id\":\"u3\"}") == Ok(grants.Person("u3", ""))
  assert api.parse_lookup("{\"id\":\"\"}") == Error(Nil)
  assert api.parse_lookup("<html>proxy</html>") == Error(Nil)
}

pub fn lookup_errors_are_readable_test() {
  assert api.lookup_error(
      404,
      "{\"message\":\"No user with this e-mail address.\"}",
    )
    == "Nobody with this e-mail address uses Atlas."
  assert api.lookup_error(400, "{\"message\":\"That is you.\"}")
    == "That is your own address."
  assert api.lookup_error(
      400,
      "{\"message\":\"An e-mail address is required.\"}",
    )
    == "Enter a complete e-mail address."
  assert api.lookup_error(429, "")
    == "Too many lookups. Wait a few minutes and try again."
  assert api.lookup_error(0, "")
    == "You are offline. Looking someone up needs a connection."
  assert api.lookup_error(401, "") == "Your session has ended. Sign in again."
  assert api.lookup_error(500, "") == "The lookup failed. Try again later."
}

pub fn plus_signs_survive_in_query_strings_test() {
  // A bare + would arrive at the server as a space.
  assert api.lookup_user("name+tag@example.com").path
    == "/api/atlas/users/lookup?email=name%2Btag%40example.com"
}

pub fn the_strava_requests_test() {
  assert api.strava_status() == Request(Get, "/api/atlas/strava/status", None)
  assert api.strava_connect() == Request(Get, "/api/atlas/strava/connect", None)
  assert api.strava_sync() == Request(Post, "/api/atlas/strava/sync", None)
  assert api.strava_disconnect()
    == Request(Delete, "/api/atlas/strava/connection", None)
}

pub fn the_strava_answers_are_read_test() {
  assert api.parse_strava_status("{\"configured\":true,\"connected\":false}")
    == Ok(api.StravaStatus(True, False))
  assert api.parse_strava_status("{\"configured\":true}") == Error(Nil)
  assert api.parse_strava_status("<html>proxy</html>") == Error(Nil)
  assert api.parse_strava_url(
      "{\"url\":\"https://www.strava.com/oauth/authorize?x=1\"}",
    )
    == Ok("https://www.strava.com/oauth/authorize?x=1")
  assert api.parse_strava_url("{\"url\":\"\"}") == Error(Nil)
  assert api.parse_strava_url("{}") == Error(Nil)
  assert api.parse_count("{\"imported\":12}", "imported") == Ok(12)
  assert api.parse_count("{\"removed\":0}", "removed") == Ok(0)
  assert api.parse_count("{\"removed\":0}", "imported") == Error(Nil)
}

pub fn strava_errors_are_readable_test() {
  assert api.strava_error(0, "")
    == "You are offline. Strava needs a connection."
  assert api.strava_error(401, "") == "Your session has ended. Sign in again."
  assert api.strava_error(404, "") == "Strava is not connected."
  assert api.strava_error(503, "") == "Strava is not set up on this server."
  assert api.strava_error(502, "")
    == "Strava could not be reached. Try again later."
  assert api.strava_error(418, "") == "That did not work (HTTP 418)."
}

pub fn the_sweep_asks_for_ids_in_order_after_the_last_one_seen_test() {
  assert api.list_ids(Plans, None)
    == Request(
      Get,
      "/api/collections/plans/records?perPage=500&sort=id&fields=id&skipTotal=1",
      None,
    )
  assert api.list_ids(Workouts, Some("abc123"))
    == Request(
      Get,
      "/api/collections/workouts/records?perPage=500&sort=id&fields=id&skipTotal=1&filter=id%20%3E%20%22abc123%22",
      None,
    )
}

pub fn the_ids_of_an_answer_are_read_in_order_test() {
  assert api.parse_ids(
      "{\"items\":[{\"id\":\"a\"},{\"id\":\"b\"}],\"page\":1,\"perPage\":500,\"totalItems\":-1,\"totalPages\":-1}",
    )
    == Ok(["a", "b"])
  assert api.parse_ids("{\"items\":[]}") == Ok([])
  assert api.parse_ids("{\"items\":[{\"title\":\"no id\"}]}") == Error(Nil)
  assert api.parse_ids("<html>proxy</html>") == Error(Nil)
}
