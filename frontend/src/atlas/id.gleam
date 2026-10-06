//// Client-generated record IDs. PocketBase accepts an ID on create if it is 15 characters of
//// `[a-z0-9]`, so a record made offline keeps its ID after sync (ADR 0004).
//// The random source is passed in, which keeps this module pure and testable.

import gleam/list
import gleam/string

pub const length = 15

const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"

/// `random(n)` must return an integer in `0..n-1`.
pub fn generate(random: fn(Int) -> Int) -> String {
  list.repeat(Nil, length)
  |> list.map(fn(_) { char_at(random(string.length(alphabet))) })
  |> string.concat
}

pub fn is_valid(id: String) -> Bool {
  string.length(id) == length
  && list.all(string.to_graphemes(id), fn(c) { string.contains(alphabet, c) })
}

fn char_at(index: Int) -> String {
  string.slice(alphabet, index, 1)
}
