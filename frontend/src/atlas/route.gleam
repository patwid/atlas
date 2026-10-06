//// The app's pages and their URLs. Pure, so it can be tested without a browser.

import gleam/uri.{type Uri}

pub type Route {
  Today
  Plans
  Plan(id: String)
  Activities
  Settings
  NotFound
}

pub fn parse(uri: Uri) -> Route {
  case uri.path_segments(uri.path) {
    [] -> Today
    ["plans"] -> Plans
    ["plans", id] -> Plan(id)
    ["activities"] -> Activities
    ["settings"] -> Settings
    _ -> NotFound
  }
}

pub fn to_path(route: Route) -> String {
  case route {
    Today -> "/"
    Plans -> "/plans"
    Plan(id) -> "/plans/" <> uri.percent_encode(id)
    Activities -> "/activities"
    Settings -> "/settings"
    NotFound -> "/"
  }
}

pub fn title(route: Route) -> String {
  case route {
    Today -> "Today"
    Plans -> "Plans"
    Plan(_) -> "Plan"
    Activities -> "Activities"
    Settings -> "Settings"
    NotFound -> "Not found"
  }
}
