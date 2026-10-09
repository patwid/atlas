import atlas/ui/form_dialog
import gleam/list
import gleam/string
import lustre/element
import lustre/element/html

fn html_of(open: Bool) -> String {
  element.to_string(
    form_dialog.view("d", open, "New plan", "the-form", "Save", Nil, [
      html.form([], []),
    ]),
  )
}

pub fn both_sets_of_buttons_submit_the_form_test() {
  let html = html_of(True)
  // The top bar's Close and Save for a phone, the bottom Cancel and filled Save for wider screens (ADR 0085).
  assert string.contains(html, "class=\"form-dialog-close\"")
  assert string.contains(html, "form-dialog-submit")
  assert string.contains(html, "form-dialog-actions")
  assert string.contains(html, "md-button-filled")
  assert list.length(string.split(html, "form=\"the-form\"")) == 3
}

pub fn a_closed_dialog_draws_nothing_inside_test() {
  let html = html_of(False)
  assert !string.contains(html, "form-dialog-actions")
}
