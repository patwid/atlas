//// For view tests: whether a field in rendered HTML carries its label. A Fluent UI text field (ADR 0133) has its
//// label as the first thing inside the element with its id, where Fluent connects it to the input.

import gleam/string

pub fn labelled(html: String, id: String, label: String) -> Bool {
  case string.split_once(html, "id=\"" <> id <> "\"") {
    Ok(#(_, after)) ->
      case string.split_once(after, ">") {
        Ok(#(_, inside)) -> string.starts_with(inside, label)
        Error(Nil) -> False
      }
    Error(Nil) -> False
  }
}
