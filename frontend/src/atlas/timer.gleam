//// One-shot timers.

import lustre/effect.{type Effect}

@external(javascript, "./timer.ffi.mjs", "after")
fn do_after(milliseconds: Int, callback: fn() -> Nil) -> Nil

pub fn after(seconds: Int, msg: msg) -> Effect(msg) {
  effect.from(fn(dispatch) { do_after(seconds * 1000, fn() { dispatch(msg) }) })
}

@external(javascript, "./timer.ffi.mjs", "afterUnheld")
fn do_after_unheld(milliseconds: Int, callback: fn() -> Nil) -> Nil

/// Like `after`, for a snackbar with an action: while the pointer is on the snackbar or the focus is in it, the time
/// does not run out, so its action can still be reached (ADR 0124).
pub fn after_unheld(seconds: Int, msg: msg) -> Effect(msg) {
  effect.from(fn(dispatch) {
    do_after_unheld(seconds * 1000, fn() { dispatch(msg) })
  })
}
