//// Whether the browser is online, as an initial value plus an effect that reports changes.
//// The browser API sits in `online.ffi.mjs`, which holds no logic.

import lustre/effect.{type Effect}

@external(javascript, "./online.ffi.mjs", "isOnline")
pub fn is_online() -> Bool

@external(javascript, "./online.ffi.mjs", "listen")
fn do_listen(dispatch: fn(Bool) -> Nil) -> Nil

pub fn listen(to to_msg: fn(Bool) -> msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    do_listen(fn(online) { dispatch(to_msg(online)) })
  })
}
