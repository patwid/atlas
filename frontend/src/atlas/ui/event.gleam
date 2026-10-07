//// Event decoders for Shoelace's custom form-control events (ADR 0037). Shoelace
//// fires `sl-input`/`sl-change` instead of the native `input`/`change`, but still
//// exposes the control's value at `event.target.value`, so these mirror
//// `lustre/event.on_input`/`on_change` exactly, just under Shoelace's event names.

import gleam/dynamic/decode
import lustre/attribute.{type Attribute}
import lustre/event

pub fn on_input(message: fn(String) -> msg) -> Attribute(msg) {
  on_value("sl-input", message)
}

pub fn on_change(message: fn(String) -> msg) -> Attribute(msg) {
  on_value("sl-change", message)
}

fn on_value(name: String, message: fn(String) -> msg) -> Attribute(msg) {
  event.on(name, {
    use value <- decode.subfield(["target", "value"], decode.string)
    decode.success(message(value))
  })
}
