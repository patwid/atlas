//// The app's pages and their URLs. Pure, so it can be tested without a browser.

import gleam/list
import gleam/option.{type Option, None, Some}
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

/// The result Strava's redirect puts in the address (`/settings?strava=connected`), if there is one.
pub fn strava_result(uri: Uri) -> Option(String) {
  case uri.query {
    None -> None
    Some(query) ->
      case uri.parse_query(query) {
        Ok(pairs) ->
          case list.key_find(pairs, "strava") {
            Ok(value) -> Some(value)
            Error(Nil) -> None
          }
        Error(Nil) -> None
      }
  }
}
