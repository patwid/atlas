//// The assignments on the device: which athlete each plan is for (ADR 0110). Home, the plan screens and the coach's
//// view of an athlete read them from here. Nothing is written here: a plan's assignment is made with the plan, and
//// no client changes it (ADR 0020, 0023).

import atlas/assignment_form.{type Row}
import atlas/collection
import atlas/records
import atlas/store
import gleam/dynamic.{type Dynamic}
import lustre/effect.{type Effect}

pub type Model {
  Model(
    /// The assignments of every plan on the device.
    rows: List(Row),
    loaded: Bool,
  )
}

pub type Msg {
  Refresh
  AssignmentsRead(Result(List(Dynamic), Nil))
}

pub fn new() -> Model {
  Model([], False)
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Assignments, fn(result) {
      dispatch(AssignmentsRead(result))
    })
  })
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Refresh -> #(model, refresh())
    AssignmentsRead(Ok(stored)) -> #(
      Model(rows: records.live(stored, records.assignment_row), loaded: True),
      effect.none(),
    )
    AssignmentsRead(Error(Nil)) -> #(model, effect.none())
  }
}
