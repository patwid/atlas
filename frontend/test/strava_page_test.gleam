import atlas/api.{StravaStatus}
import atlas/http.{Response}
import atlas/strava_page.{
  Answered, CancelClicked, ConnectClicked, ConnectReply, DisconnectClicked,
  DisconnectConfirmed, DisconnectReply, Fetch, Info, Known, Model, Navigate,
  Problem, Refresh, Returned, StatusReply, SyncClicked, SyncNow, SyncReply,
}
import gleam/option.{None, Some}
import gleam/string
import lustre/element

fn update(model: strava_page.Model, msg: strava_page.Msg) {
  let #(next, _, actions) = strava_page.update(model, msg)
  #(next, actions)
}

fn connected() -> strava_page.Model {
  Model(..strava_page.new(), status: Known(StravaStatus(True, True)))
}

fn disconnected() -> strava_page.Model {
  Model(..strava_page.new(), status: Known(StravaStatus(True, False)))
}

pub fn refreshing_asks_the_server_test() {
  let #(model, actions) = update(strava_page.new(), Refresh)
  assert model.status == strava_page.Checking
  assert actions == [Fetch(api.strava_status(), StatusReply)]
}

pub fn the_status_answer_is_shown_test() {
  let #(model, _) =
    update(
      strava_page.new(),
      Answered(
        StatusReply,
        Response(200, "{\"configured\":true,\"connected\":true}"),
      ),
    )
  assert model.status == Known(StravaStatus(True, True))
}

pub fn a_failed_status_check_is_explained_not_fatal_test() {
  let #(model, _) =
    update(strava_page.new(), Answered(StatusReply, Response(0, "")))
  assert model.status
    == strava_page.Unavailable("You are offline. Strava needs a connection.")
  let #(model, _) =
    update(strava_page.new(), Answered(StatusReply, Response(200, "garbage")))
  let assert strava_page.Unavailable(_) = model.status
}

pub fn connecting_asks_for_the_address_then_leaves_for_strava_test() {
  let #(asked, actions) = update(disconnected(), ConnectClicked)
  assert asked.busy
  assert actions == [Fetch(api.strava_connect(), ConnectReply)]
  let #(still_busy, actions) =
    update(
      asked,
      Answered(
        ConnectReply,
        Response(
          200,
          "{\"url\":\"https://www.strava.com/oauth/authorize?x=1\"}",
        ),
      ),
    )
  assert actions == [Navigate("https://www.strava.com/oauth/authorize?x=1")]
  // The page is about to be left: the button stays disabled.
  assert still_busy.busy
}

pub fn a_second_click_while_busy_does_nothing_test() {
  let #(asked, _) = update(disconnected(), ConnectClicked)
  let #(same, actions) = update(asked, ConnectClicked)
  assert actions == []
  assert same == asked
}

pub fn a_failed_connect_request_says_why_and_frees_the_button_test() {
  let #(asked, _) = update(disconnected(), ConnectClicked)
  let #(model, actions) =
    update(asked, Answered(ConnectReply, Response(503, "")))
  assert actions == []
  assert !model.busy
  assert model.message == Some(Problem("Strava is not set up on this server."))
  let #(model, _) = update(asked, Answered(ConnectReply, Response(200, "{}")))
  assert !model.busy
}

pub fn importing_again_reports_the_count_and_starts_a_sync_test() {
  let #(asked, actions) = update(connected(), SyncClicked)
  assert actions == [Fetch(api.strava_sync(), SyncReply)]
  let #(model, actions) =
    update(asked, Answered(SyncReply, Response(200, "{\"imported\":12}")))
  assert model.message
    == Some(Info("Imported 12 activities from the last 30 days."))
  assert !model.busy
  assert actions == [SyncNow]
}

pub fn a_failed_import_says_why_test() {
  let #(asked, _) = update(connected(), SyncClicked)
  let #(model, actions) = update(asked, Answered(SyncReply, Response(502, "")))
  assert model.message
    == Some(Problem("Strava could not be reached. Try again later."))
  assert actions == []
}

pub fn disconnecting_needs_a_second_click_test() {
  let #(asked, actions) = update(connected(), DisconnectClicked)
  assert asked.confirming
  assert actions == []
  let #(cancelled, _) = update(asked, CancelClicked)
  assert !cancelled.confirming
  let #(going, actions) = update(asked, DisconnectConfirmed)
  assert going.busy
  assert !going.confirming
  assert actions == [Fetch(api.strava_disconnect(), DisconnectReply)]
}

pub fn disconnected_means_not_connected_and_the_removals_are_synced_test() {
  let #(going, _) = update(connected(), DisconnectConfirmed)
  let #(model, actions) =
    update(going, Answered(DisconnectReply, Response(200, "{\"removed\":7}")))
  assert model.status == Known(StravaStatus(True, False))
  assert model.message
    == Some(Info(
      "Strava is disconnected. 7 activities from Strava were removed from Atlas.",
    ))
  assert actions == [SyncNow]
}

pub fn coming_back_from_strava_connected_checks_again_and_syncs_test() {
  let #(model, actions) = update(strava_page.new(), Returned("connected"))
  assert model.message
    == Some(Info("Strava is connected. Your last 30 days are being imported."))
  assert actions == [Fetch(api.strava_status(), StatusReply), SyncNow]
}

pub fn coming_back_with_a_problem_explains_it_test() {
  let result = fn(text) { update(strava_page.new(), Returned(text)).0.message }
  assert result("denied") == Some(Problem("Strava access was not granted."))
  assert result("scope")
    == Some(Problem(
      "Atlas needs permission to read your activities. Try again and keep that box ticked.",
    ))
  assert result("taken")
    == Some(Problem(
      "This Strava account is already used by another Atlas user.",
    ))
  assert result("something else") == None
}

fn html_of(model: strava_page.Model) -> String {
  element.to_string(strava_page.view(model))
}

pub fn not_connected_offers_the_button_and_the_attribution_test() {
  let html = html_of(disconnected())
  assert string.contains(html, "Connect with Strava")
  assert string.contains(html, "Powered by Strava")
  assert !string.contains(html, "Disconnect")
}

pub fn connected_offers_import_and_disconnect_test() {
  let html = html_of(connected())
  assert string.contains(html, "Connected to Strava")
  assert string.contains(html, "Import the last 30 days again")
  assert string.contains(html, ">Disconnect<")
  assert string.contains(html, "Powered by Strava")
  assert !string.contains(html, "Connect with Strava")
}

pub fn an_unconfigured_server_says_so_and_shows_no_button_test() {
  let html =
    html_of(
      Model(..strava_page.new(), status: Known(StravaStatus(False, False))),
    )
  assert string.contains(html, "Strava is not set up on this server.")
  assert !string.contains(html, "Connect with Strava")
}

pub fn the_disconnect_question_has_a_way_out_test() {
  let html = html_of(Model(..connected(), confirming: True))
  assert string.contains(
    html,
    "Disconnect Strava and remove its activities from Atlas?",
  )
  assert string.contains(html, "Yes, disconnect")
  assert string.contains(html, "Keep it connected")
}

pub fn busy_disables_the_buttons_test() {
  assert string.contains(
    html_of(Model(..disconnected(), busy: True)),
    "disabled",
  )
  assert !string.contains(html_of(disconnected()), "disabled")
}

pub fn messages_are_announced_test() {
  let info =
    html_of(
      Model(
        ..connected(),
        message: Some(Info("Imported 3 activities from the last 30 days.")),
      ),
    )
  assert string.contains(info, "role=\"status\"")
  let problem =
    html_of(
      Model(
        ..connected(),
        message: Some(Problem("Strava access was not granted.")),
      ),
    )
  assert string.contains(problem, "role=\"alert\"")
}

pub fn checking_and_unavailable_states_are_shown_test() {
  assert string.contains(html_of(strava_page.new()), "Checking")
  let off =
    html_of(
      Model(
        ..strava_page.new(),
        status: strava_page.Unavailable(
          "You are offline. Strava needs a connection.",
        ),
      ),
    )
  assert string.contains(off, "You are offline")
}

pub fn only_web_addresses_are_followed_test() {
  let answer = fn(url) {
    let #(asked, _) = update(disconnected(), ConnectClicked)
    update(
      asked,
      Answered(ConnectReply, Response(200, "{\"url\":\"" <> url <> "\"}")),
    )
  }
  assert answer("https://www.strava.com/oauth/authorize?a=1").1
    == [Navigate("https://www.strava.com/oauth/authorize?a=1")]
  assert answer("http://127.0.0.1:9/oauth/authorize").1
    == [Navigate("http://127.0.0.1:9/oauth/authorize")]
  let refused = answer("javascript:alert(1)")
  assert refused.1 == []
  assert refused.0.message
    == Some(Problem("Strava sent an address this app cannot open."))
  assert !refused.0.busy
  assert answer("not an address").1 == []
  assert answer("/relative/path").1 == []
}
