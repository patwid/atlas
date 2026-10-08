//// Focus an element after the next render: the first field of a form that just opened.

import lustre/effect.{type Effect}

pub fn soon(id: String) -> Effect(msg) {
  effect.from(fn(_) { focus_soon(id) })
}

@external(javascript, "./focus.ffi.mjs", "focusSoon")
fn focus_soon(id: String) -> Nil
