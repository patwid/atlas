//// Connecting Strava, in Settings: connect, import again, disconnect. The server does the OAuth exchange and
//// holds the tokens (ADR 0012); this screen starts it and shows the state (ADR 0027). Own state and messages;
//// requests, the move to Strava's page and "sync now" come back as `Action`s.

import atlas/api.{type StravaStatus}
import atlas/http
import atlas/ui/button
import atlas/ui/dialog
import atlas/ui/error
import atlas/ui/layout
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/uri
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

const confirm_dialog_id = "confirm-disconnect-strava"

pub type Status {
  /// Not asked yet.
  Unknown
  Checking
  Known(StravaStatus)
  /// The server could not be asked (offline, or a problem).
  Unavailable(String)
}

pub type Message {
  Info(String)
  Problem(String)
}

pub type Model {
  Model(
    status: Status,
    /// A request is under way, or the browser is on its way to Strava.
    busy: Bool,
    message: Option(Message),
    /// "Disconnect" was clicked once.
    confirming: Bool,
  )
}

/// Which request an answer belongs to.
pub type Reply {
  StatusReply
  ConnectReply
  SyncReply
  DisconnectReply
}

pub type Msg {
  Refresh
  Answered(Reply, http.Response)
  ConnectClicked
  SyncClicked
  DisconnectClicked
  DisconnectConfirmed
  CancelClicked
  /// The browser came back from Strava with this result (`connected`, `denied`, `scope` or `taken`).
  Returned(String)
}

pub type Action {
  Fetch(api.Request, Reply)
  /// Send the browser to Strava's page.
  Navigate(String)
  /// Run a sync so that imported (or removed) activities reach the device.
  SyncNow
}

pub fn new() -> Model {
  Model(Unknown, False, None, False)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(Model(..model, status: Checking), effect.none(), [
      Fetch(api.strava_status(), StatusReply),
    ])

    ConnectClicked ->
      case model.busy {
        True -> #(model, effect.none(), [])
        False -> #(Model(..model, busy: True, message: None), effect.none(), [
          Fetch(api.strava_connect(), ConnectReply),
        ])
      }

    SyncClicked ->
      case model.busy {
        True -> #(model, effect.none(), [])
        False -> #(Model(..model, busy: True, message: None), effect.none(), [
          Fetch(api.strava_sync(), SyncReply),
        ])
      }

    DisconnectClicked -> #(
      Model(..model, confirming: True),
      dialog.show(confirm_dialog_id),
      [],
    )

    CancelClicked -> #(Model(..model, confirming: False), effect.none(), [])

    DisconnectConfirmed ->
      case model.busy {
        True -> #(model, effect.none(), [])
        False -> #(
          Model(..model, busy: True, confirming: False, message: None),
          effect.none(),
          [Fetch(api.strava_disconnect(), DisconnectReply)],
        )
      }

    Answered(StatusReply, response) ->
      case response.status, api.parse_strava_status(response.body) {
        200, Ok(status) -> #(
          Model(..model, status: Known(status)),
          effect.none(),
          [],
        )
        status, _ -> #(
          Model(
            ..model,
            status: Unavailable(api.strava_error(status, response.body)),
          ),
          effect.none(),
          [],
        )
      }

    Answered(ConnectReply, response) ->
      case response.status, api.parse_strava_url(response.body) {
        200, Ok(url) ->
          case can_open(url) {
            True -> #(model, effect.none(), [Navigate(url)])
            False -> #(
              Model(
                ..model,
                busy: False,
                message: Some(Problem(
                  "Strava sent an address this app cannot open.",
                )),
              ),
              effect.none(),
              [],
            )
          }
        status, _ -> #(
          Model(
            ..model,
            busy: False,
            message: Some(Problem(api.strava_error(status, response.body))),
          ),
          effect.none(),
          [],
        )
      }

    Answered(SyncReply, response) ->
      case response.status, api.parse_count(response.body, "imported") {
        200, Ok(count) -> #(
          Model(
            ..model,
            busy: False,
            message: Some(Info(
              "Imported "
              <> int.to_string(count)
              <> " activities from the last 30 days.",
            )),
          ),
          effect.none(),
          [SyncNow],
        )
        status, _ -> #(
          Model(
            ..model,
            busy: False,
            message: Some(Problem(api.strava_error(status, response.body))),
          ),
          effect.none(),
          [],
        )
      }

    Answered(DisconnectReply, response) ->
      case response.status, api.parse_count(response.body, "removed") {
        200, Ok(count) -> #(
          Model(
            ..model,
            busy: False,
            status: Known(api.StravaStatus(True, False)),
            message: Some(Info(
              "Strava is disconnected. "
              <> int.to_string(count)
              <> " activities from Strava were removed from Atlas.",
            )),
          ),
          effect.none(),
          [SyncNow],
        )
        status, _ -> #(
          Model(
            ..model,
            busy: False,
            message: Some(Problem(api.strava_error(status, response.body))),
          ),
          effect.none(),
          [],
        )
      }

    Returned(result) ->
      case result {
        "connected" -> #(
          Model(
            ..model,
            busy: False,
            status: Checking,
            message: Some(Info(
              "Strava is connected. Your last 30 days are being imported.",
            )),
          ),
          effect.none(),
          [Fetch(api.strava_status(), StatusReply), SyncNow],
        )
        "denied" -> #(
          Model(
            ..model,
            message: Some(Problem("Strava access was not granted.")),
          ),
          effect.none(),
          [],
        )
        "scope" -> #(
          Model(
            ..model,
            message: Some(Problem(
              "Atlas needs permission to read your activities. Try again and keep that box ticked.",
            )),
          ),
          effect.none(),
          [],
        )
        "taken" -> #(
          Model(
            ..model,
            message: Some(Problem(
              "This Strava account is already used by another Atlas user.",
            )),
          ),
          effect.none(),
          [],
        )
        _ -> #(model, effect.none(), [])
      }
  }
}

/// Only web addresses are followed: the server's answer is not trusted to send the browser anywhere else.
fn can_open(url: String) -> Bool {
  case uri.parse(url) {
    Ok(parsed) ->
      case parsed.scheme, parsed.host {
        Some("https"), Some(_) | Some("http"), Some(_) -> True
        _, _ -> False
      }
    Error(Nil) -> False
  }
}

// VIEWS -------------------------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  html.section([class("strava")], [
    html.h2([], [html.text("Strava")]),
    case model.status {
      Unknown | Checking -> html.p([class("muted")], [html.text("Checking…")])
      Unavailable(reason) -> html.p([class("muted")], [html.text(reason)])
      Known(status) -> status_view(model, status)
    },
    case model.message {
      Some(Info(text)) -> html.p([attribute.role("status")], [html.text(text)])
      Some(Problem(text)) -> error.message(text)
      None -> element.none()
    },
  ])
}

fn status_view(model: Model, status: StravaStatus) -> Element(Msg) {
  case status.configured, status.connected {
    False, _ ->
      html.p([class("muted")], [
        html.text("Strava is not set up on this server."),
      ])
    True, False ->
      html.div([], [
        html.p([class("muted")], [
          html.text(
            "Bring your runs in from Strava automatically. Atlas can then match them to your plans.",
          ),
        ]),
        // Strava's own button image, unchanged, as their brand rules require: the plain, unstyled
        // base, not one of Atlas's own button variants.
        button.button(
          [
            attribute.type_("button"),
            class("strava-connect"),
            attribute.disabled(model.busy),
            event.on_click(ConnectClicked),
          ],
          [
            html.img([
              attribute.src("/strava/btn_strava_connect_with_orange.svg"),
              attribute.alt("Connect with Strava"),
              attribute.width(237),
              attribute.height(48),
            ]),
          ],
        ),
        attribution(),
      ])
    True, True ->
      html.div([], [
        html.p([], [
          html.text("Connected to Strava. New activities arrive by themselves."),
        ]),
        layout.actions([
          button.secondary(
            [
              attribute.type_("button"),
              attribute.disabled(model.busy),
              event.on_click(SyncClicked),
            ],
            [html.text("Import the last 30 days again")],
          ),
          button.secondary(
            [
              attribute.type_("button"),
              attribute.disabled(model.busy),
              event.on_click(DisconnectClicked),
            ],
            [html.text("Disconnect")],
          ),
          dialog.view(
            confirm_dialog_id,
            "Disconnect Strava and remove its activities from Atlas?",
            CancelClicked,
            [
              button.danger(
                [attribute.type_("submit"), event.on_click(DisconnectConfirmed)],
                [html.text("Yes, disconnect")],
              ),
              button.secondary(
                [attribute.type_("submit"), event.on_click(CancelClicked)],
                [html.text("Keep it connected")],
              ),
            ],
          ),
        ]),
        attribution(),
      ])
  }
}

/// Strava's API agreement asks for this wherever its data is used: their logo, unchanged, small and
/// apart from our own name.
fn attribution() -> Element(Msg) {
  html.p([class("attribution")], [
    html.img([
      attribute.src("/strava/api_logo_pwrdBy_strava_horiz_orange.svg"),
      attribute.alt("Powered by Strava"),
      attribute.width(146),
      attribute.height(15),
    ]),
  ])
}
