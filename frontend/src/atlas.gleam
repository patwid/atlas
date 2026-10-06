//// Atlas: an offline-capable PWA for running training. This is the app shell (ADR 0013):
//// routing, the page frame, the online indicator and service worker registration.

import atlas/online
import atlas/pwa
import atlas/route.{type Route}
import atlas/shell
import gleam/result
import gleam/uri.{type Uri}
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import modem

pub type Model {
  Model(route: Route, online: Bool)
}

pub type Msg {
  RouteChanged(Uri)
  OnlineChanged(Bool)
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
  #(
    Model(route:, online: online.is_online()),
    effect.batch([
      modem.init(RouteChanged),
      online.listen(OnlineChanged),
      pwa.register_service_worker(),
    ]),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    RouteChanged(uri) -> #(
      Model(..model, route: route.parse(uri)),
      effect.none(),
    )
    OnlineChanged(online) -> #(Model(..model, online:), effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  shell.view(model.route, model.online, page(model.route))
}

fn page(current: Route) -> Element(Msg) {
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
    route.Settings ->
      shell.empty("Settings", "Account, Strava and coach access will be here.")
    route.NotFound ->
      shell.empty("Page not found", "Use the tabs below to get back.")
  }
}
