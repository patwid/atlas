import atlas/route.{Activities, NotFound, Plan, Plans, Settings, Today}
import gleam/option
import gleam/uri

fn parse(path: String) -> route.Route {
  let assert Ok(u) = uri.parse(path)
  route.parse(u)
}

pub fn parses_each_page_test() {
  assert parse("/") == Today
  assert parse("") == Today
  assert parse("/plans") == Plans
  assert parse("/plans/") == Plans
  assert parse("/plans/abc123") == Plan("abc123")
  assert parse("/activities") == Activities
  assert parse("/settings?strava=connected") == Settings
  assert parse("/settings/zones") == route.SettingsPage(route.Zones)
}

pub fn unknown_paths_are_not_found_test() {
  assert parse("/nope") == NotFound
  assert parse("/plans/a/b") == NotFound
  assert parse("/settings/nope") == NotFound
}

pub fn to_path_round_trips_test() {
  let routes = [
    Today,
    Plans,
    Plan("abc123"),
    Activities,
    Settings,
    route.SettingsPage(route.Zones),
    route.SettingsPage(route.Coaches),
    route.SettingsPage(route.Strava),
    route.Athletes,
    route.Athlete("ana1"),
  ]
  assert list_map_parse(routes) == routes
}

pub fn ids_are_percent_encoded_test() {
  assert route.to_path(Plan("a b/c")) == "/plans/a%20b%2Fc"
}

fn list_map_parse(routes: List(route.Route)) -> List(route.Route) {
  case routes {
    [] -> []
    [r, ..rest] -> [parse(route.to_path(r)), ..list_map_parse(rest)]
  }
}

pub fn the_strava_result_is_read_from_the_address_test() {
  let result = fn(text) {
    let assert Ok(u) = uri.parse(text)
    route.strava_result(u)
  }
  assert result("/settings?strava=connected") == option.Some("connected")
  assert result("/settings?x=1&strava=denied") == option.Some("denied")
  assert result("/settings") == option.None
  assert result("/settings?other=1") == option.None
  assert result("/?strava=taken") == option.Some("taken")
}

pub fn the_athlete_pages_are_routes_test() {
  assert parse("/athletes") == route.Athletes
  assert parse("/athletes/ana1") == route.Athlete("ana1")
  assert parse("/athletes/a/b") == NotFound
  assert route.to_path(route.Athlete("a b")) == "/athletes/a%20b"
  assert route.title(route.Athletes) == "Athletes"
  assert route.title(route.Athlete("x")) == "Athlete"
}
