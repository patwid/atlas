import atlas.{Model, OnlineChanged, RouteChanged}
import atlas/route
import gleam/uri
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn route_changes_update_the_model_test() {
  let assert Ok(u) = uri.parse("/plans/p1")
  let #(model, _) = atlas.update(Model(route.Today, True), RouteChanged(u))
  assert model.route == route.Plan("p1")
}

pub fn going_offline_is_reflected_test() {
  let #(model, _) = atlas.update(Model(route.Today, True), OnlineChanged(False))
  assert !model.online
  let #(model, _) = atlas.update(model, OnlineChanged(True))
  assert model.online
}
