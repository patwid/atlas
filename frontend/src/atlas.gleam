//// Atlas: an offline-capable PWA for running training. This is the app shell (ADR 0013) with
//// sign-in (ADR 0017): routing, the page frame, the online indicator and the session.

import atlas/api
import atlas/auth.{type Session}
import atlas/clock
import atlas/http
import atlas/online
import atlas/pwa
import atlas/route.{type Route}
import atlas/shell
import atlas/signin
import atlas/storage
import gleam/option.{None, Some}
import gleam/result
import gleam/uri.{type Uri}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem

pub const session_key = "atlas.session"

pub type Auth {
  SignedOut(form: signin.Form)
  SignedIn(session: Session)
}

pub type Model {
  Model(route: Route, online: Bool, auth: Auth)
}

pub type Msg {
  RouteChanged(Uri)
  OnlineChanged(Bool)
  EmailChanged(String)
  PasswordChanged(String)
  SignInSubmitted
  SignInResponded(http.Response)
  RefreshResponded(http.Response)
  SignOutClicked
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let route =
    modem.initial_uri()
    |> result.map(route.parse)
    |> result.unwrap(route.Today)
  let auth = case
    storage.get(session_key) |> result.try(auth.session_from_json)
  {
    Ok(session) -> SignedIn(session)
    Error(Nil) -> SignedOut(signin.empty())
  }
  let is_online = online.is_online()
  #(
    Model(route:, online: is_online, auth:),
    effect.batch([
      modem.init(RouteChanged),
      online.listen(OnlineChanged),
      pwa.register_service_worker(),
      case is_online {
        True -> refresh_if_due(auth)
        False -> effect.none()
      },
    ]),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    RouteChanged(uri) -> #(
      Model(..model, route: route.parse(uri)),
      effect.none(),
    )

    // Coming back online is when an expired or soon-to-expire session gets refreshed.
    OnlineChanged(is_online) -> #(
      Model(..model, online: is_online),
      case is_online {
        True -> refresh_if_due(model.auth)
        False -> effect.none()
      },
    )

    EmailChanged(email) ->
      with_form(model, fn(form) { signin.Form(..form, email: email) })
    PasswordChanged(password) ->
      with_form(model, fn(form) { signin.Form(..form, password: password) })

    SignInSubmitted ->
      case model.auth {
        SignedOut(form) if form.busy -> #(model, effect.none())
        SignedOut(form) ->
          case form.email == "" || form.password == "" {
            True -> #(
              Model(
                ..model,
                auth: SignedOut(
                  signin.Form(
                    ..form,
                    error: Some("Enter your e-mail and password."),
                  ),
                ),
              ),
              effect.none(),
            )
            False -> #(
              Model(
                ..model,
                auth: SignedOut(signin.Form(..form, busy: True, error: None)),
              ),
              http.send(
                api.sign_in(form.email, form.password),
                None,
                SignInResponded,
              ),
            )
          }
        SignedIn(_) -> #(model, effect.none())
      }

    SignInResponded(response) ->
      case
        model.auth,
        response.status,
        auth.session_from_response(response.body)
      {
        SignedOut(_), 200, Ok(session) -> #(
          Model(..model, auth: SignedIn(session)),
          remember(session),
        )
        SignedOut(form), status, _ -> #(
          Model(
            ..model,
            auth: SignedOut(
              signin.Form(
                ..form,
                password: "",
                busy: False,
                error: Some(auth.sign_in_error(status, response.body)),
              ),
            ),
          ),
          effect.none(),
        )
        SignedIn(_), _, _ -> #(model, effect.none())
      }

    RefreshResponded(response) ->
      case model.auth, response.status {
        SignedIn(session), 200 ->
          case auth.session_from_response(response.body) {
            // A refresh must stay the same account; anything else is ignored.
            Ok(fresh) if fresh.user_id == session.user_id -> {
              let updated = auth.with_token(session, fresh.token)
              #(Model(..model, auth: SignedIn(updated)), remember(updated))
            }
            _ -> #(model, effect.none())
          }
        // The server no longer accepts the token. Nothing else is deleted: local data stays
        // for the next sign-in of the same user (ADR 0017).
        SignedIn(_), 401 -> #(
          Model(
            ..model,
            auth: SignedOut(
              signin.Form(
                ..signin.empty(),
                error: Some("Your session expired. Sign in again."),
              ),
            ),
          ),
          forget(),
        )
        // Offline, a server hiccup or anything else: stay signed in and try again later.
        _, _ -> #(model, effect.none())
      }

    SignOutClicked -> #(
      Model(..model, auth: SignedOut(signin.empty())),
      forget(),
    )
  }
}

fn with_form(
  model: Model,
  change: fn(signin.Form) -> signin.Form,
) -> #(Model, Effect(Msg)) {
  case model.auth {
    SignedOut(form) -> #(
      Model(..model, auth: SignedOut(change(form))),
      effect.none(),
    )
    SignedIn(_) -> #(model, effect.none())
  }
}

fn remember(session: Session) -> Effect(Msg) {
  effect.from(fn(_) { storage.set(session_key, auth.session_to_json(session)) })
}

fn forget() -> Effect(Msg) {
  effect.from(fn(_) { storage.remove(session_key) })
}

/// Asks the server for a fresh token when the stored one is close to expiring (or already expired).
/// The clock is read when the effect runs, so `update` stays free of the current time.
fn refresh_if_due(state: Auth) -> Effect(Msg) {
  case state {
    SignedOut(_) -> effect.none()
    SignedIn(session) ->
      effect.from(fn(dispatch) {
        case auth.should_refresh(session.token, clock.now_seconds()) {
          True ->
            http.perform(api.refresh(), Some(session.token), fn(response) {
              dispatch(RefreshResponded(response))
            })
          False -> Nil
        }
      })
  }
}

fn view(model: Model) -> Element(Msg) {
  case model.auth {
    SignedOut(form) ->
      signin.view(form, EmailChanged, PasswordChanged, SignInSubmitted)
    SignedIn(session) ->
      shell.view(model.route, model.online, page(model.route, session))
  }
}

fn page(current: Route, session: Session) -> Element(Msg) {
  case current {
    route.Today ->
      shell.empty(
        "Nothing planned yet",
        "Today's workout and what you have done will show up here.",
      )
    route.Plans ->
      shell.empty(
        "No plans yet",
        "Create a training plan or open a shared one.",
      )
    route.Plan(id) ->
      shell.empty("Plan " <> id, "This plan is not available offline yet.")
    route.Activities ->
      shell.empty(
        "No activities yet",
        "Connect Strava or import a FIT file to see your runs.",
      )
    route.Settings -> settings(session)
    route.NotFound ->
      shell.empty("Page not found", "Use the tabs below to get back.")
  }
}

fn settings(session: Session) -> Element(Msg) {
  html.section([attribute.class("settings")], [
    html.h2([], [html.text("Account")]),
    html.p([], [
      html.text(case session.name {
        "" -> session.email
        name -> name <> " (" <> session.email <> ")"
      }),
    ]),
    html.button([attribute.type_("button"), event.on_click(SignOutClicked)], [
      html.text("Sign out"),
    ]),
  ])
}
