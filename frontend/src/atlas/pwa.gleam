//// Service worker registration. The worker itself is plain JavaScript in `assets/sw.js` (ADR 0003).

import lustre/effect.{type Effect}

@external(javascript, "./pwa.ffi.mjs", "registerServiceWorker")
fn do_register() -> Nil

pub fn register_service_worker() -> Effect(msg) {
  effect.from(fn(_dispatch) { do_register() })
}
