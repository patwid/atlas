//// Fluent UI's web components (ADR 0133, spike). `define` is called once, before the app starts, so the
//// `fluent-*` custom elements exist when the first view is drawn.

@external(javascript, "./fluent.ffi.mjs", "define")
pub fn define() -> Nil
