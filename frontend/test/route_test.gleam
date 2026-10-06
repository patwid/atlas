import atlas/route.{Activities, NotFound, Plan, Plans, Settings, Today}
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
}

pub fn unknown_paths_are_not_found_test() {
  assert parse("/nope") == NotFound
  assert parse("/plans/a/b") == NotFound
}

pub fn to_path_round_trips_test() {
  let routes = [Today, Plans, Plan("abc123"), Activities, Settings]
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
