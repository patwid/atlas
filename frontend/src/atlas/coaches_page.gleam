//// Coach grants on the device: who may see the user's training, and whose training the user may see.
//// Reading comes first (the assignment screens need it); the screen to manage grants follows in Settings.

import atlas/collection
import atlas/grants.{type Grant}
import atlas/records
import atlas/store
import gleam/dynamic.{type Dynamic}
import lustre/effect.{type Effect}

pub type Model {
  Model(grants: List(Grant), loaded: Bool)
}

pub type Msg {
  Refresh
  GrantsRead(Result(List(Dynamic), Nil))
}

pub fn new() -> Model {
  Model([], False)
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.CoachGrants, fn(result) {
      dispatch(GrantsRead(result))
    })
  })
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Refresh -> #(model, refresh())
    GrantsRead(Ok(stored)) -> #(
      Model(grants: records.live(stored, records.grant), loaded: True),
      effect.none(),
    )
    GrantsRead(Error(Nil)) -> #(model, effect.none())
  }
}
