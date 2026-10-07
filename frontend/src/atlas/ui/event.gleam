//// Event decoders for Web Awesome's form-control and dialog events (ADR 0038, 0039). Unlike
//// Shoelace, which fired its own `sl-input`/`sl-change` events, Web Awesome's form controls
//// fire native `input`/`change` — but these still exist as thin wrappers (rather than using
//// `lustre/event.on_input`/`on_change` directly) because they, like Shoelace's, read the
//// value from `event.target.value`.

import gleam/dynamic/decode
import lustre/attribute.{type Attribute}
import lustre/event

pub fn on_input(message: fn(String) -> msg) -> Attribute(msg) {
  on_value("input", message)
}

pub fn on_change(message: fn(String) -> msg) -> Attribute(msg) {
  on_value("change", message)
}

/// Fires whenever a `wa-dialog` is requested to close, for any reason: its own header close
/// button, Escape, a light-dismiss backdrop click, or a button inside it. Wire this to the same
/// message a `wa-dialog`'s own cancel button sends, so the dialog's `open` attribute (driven by
/// the model) and its actual open/closed state can't drift apart.
pub fn on_hide(message: msg) -> Attribute(msg) {
  event.on("wa-hide", decode.success(message))
}

fn on_value(name: String, message: fn(String) -> msg) -> Attribute(msg) {
  event.on(name, {
    use value <- decode.subfield(["target", "value"], decode.string)
    decode.success(message(value))
  })
}
