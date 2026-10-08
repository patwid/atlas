//// Page-wide interaction details that need the DOM (ADR 0051): the ripple on buttons, list rows and navigation, and
//// the app bar's color once the page scrolls. Installed once, when the app starts.

import lustre/effect.{type Effect}

@external(javascript, "./interaction.ffi.mjs", "install")
fn do_install() -> Nil

pub fn install() -> Effect(msg) {
  effect.from(fn(_dispatch) { do_install() })
}
