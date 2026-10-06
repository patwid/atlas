//// One-shot timers.

import lustre/effect.{type Effect}

@external(javascript, "./timer.ffi.mjs", "after")
fn do_after(milliseconds: Int, callback: fn() -> Nil) -> Nil

pub fn after(seconds: Int, msg: msg) -> Effect(msg) {
  effect.from(fn(dispatch) { do_after(seconds * 1000, fn() { dispatch(msg) }) })
}
