//// Files the user picks from the device, read in the browser and never uploaded (ADR 0100), and files made in the
//// browser for the user to save, such as a workout for a watch (ADR 0122).

import lustre/effect.{type Effect}

/// Opens the picker of the file input with this ID.
pub fn pick(id: String) -> Effect(msg) {
  effect.from(fn(_) { do_pick(id) })
}

/// Reads the file chosen in the file input with this ID: its name, and its bytes or `Error` when it could not
/// be read.
pub fn read(
  id: String,
  to_msg: fn(String, Result(BitArray, Nil)) -> msg,
) -> Effect(msg) {
  effect.from(fn(dispatch) {
    do_read(id, fn(ok, name, bytes) {
      dispatch(
        to_msg(name, case ok {
          True -> Ok(bytes)
          False -> Error(Nil)
        }),
      )
    })
  })
}

/// Hands the user a file to save, called `name`. The bytes are made when the effect runs, so they can read the clock.
pub fn save(name: String, bytes: fn() -> BitArray) -> Effect(msg) {
  effect.from(fn(_) { do_save(name, bytes()) })
}

@external(javascript, "./file.ffi.mjs", "pick")
fn do_pick(id: String) -> Nil

@external(javascript, "./file.ffi.mjs", "read")
fn do_read(id: String, callback: fn(Bool, String, BitArray) -> Nil) -> Nil

@external(javascript, "./file.ffi.mjs", "save")
fn do_save(name: String, bytes: BitArray) -> Nil
