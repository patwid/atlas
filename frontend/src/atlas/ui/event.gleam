//// Event decoders for Web Awesome's form-control events (ADR 0038). Unlike Shoelace,
//// which fired its own `sl-input`/`sl-change` events, Web Awesome's form controls fire
//// native `input`/`change` — but these still exist as thin wrappers (rather than using
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

fn on_value(name: String, message: fn(String) -> msg) -> Attribute(msg) {
  event.on(name, {
    use value <- decode.subfield(["target", "value"], decode.string)
    decode.success(message(value))
  })
}
