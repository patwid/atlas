//// Delete now, undo for a few seconds (ADR 0056): Material 3's pattern for an action that can be taken back, in
//// place of a confirmation dialog. A page keeps one `Undo`; a delete hides the item at once and shows a snackbar
//// with Undo, and the page writes the delete only when the snackbar goes (after `seconds`, or when it is closed)
//// or when a second delete starts. Undo before then cancels it, so nothing was ever written.
////
//// If the app is closed while a delete waits, the delete is lost and the item stays: the safe way to fail.

import atlas/timer
import atlas/ui/snackbar
import gleam/option.{type Option, None, Some}
import lustre/effect.{type Effect}
import lustre/element.{type Element}

/// How long the snackbar stays before the delete is written.
pub const seconds = 6

pub type Undo {
  Undo(
    /// The delete waiting to be written: its number and the item's id.
    pending: Option(#(Int, String)),
    started: Int,
  )
}

pub fn new() -> Undo {
  Undo(None, 0)
}

/// Starts deleting `id`. Returns the new state, an earlier delete that must be written now, and the timer that
/// writes this one: `expired` is the page's message for the end of the wait.
pub fn start(
  undo: Undo,
  id: String,
  expired: fn(Int) -> msg,
) -> #(Undo, Option(String), Effect(msg)) {
  let n = undo.started + 1
  #(
    Undo(Some(#(n, id)), n),
    option.map(undo.pending, fn(p) { p.1 }),
    timer.after(seconds, expired(n)),
  )
}

/// The wait numbered `n` is over: the id to delete now, if that delete is still waiting.
pub fn expire(undo: Undo, n: Int) -> #(Undo, Option(String)) {
  case undo.pending {
    Some(#(waiting, id)) if waiting == n -> #(
      Undo(..undo, pending: None),
      Some(id),
    )
    _ -> #(undo, None)
  }
}

pub fn cancel(undo: Undo) -> Undo {
  Undo(..undo, pending: None)
}

/// Whether `id` is being deleted, so the page leaves it out.
pub fn hides(undo: Undo, id: String) -> Bool {
  case undo.pending {
    Some(#(_, waiting)) -> waiting == id
    None -> False
  }
}

/// The snackbar while a delete waits: `text` such as "Activity deleted", Undo, and closing it writes the delete.
pub fn snackbar(
  undo: Undo,
  text: String,
  on_undo: msg,
  expired: fn(Int) -> msg,
) -> Element(msg) {
  case undo.pending {
    Some(#(n, _)) ->
      snackbar.view(text, Some(snackbar.Act("Undo", on_undo)), expired(n))
    None -> element.none()
  }
}
