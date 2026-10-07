//// The sign-in page. Messages are passed in so this module does not depend on the app's `Msg`.

import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Form {
  Form(email: String, password: String, busy: Bool, error: Option(String))
}

pub fn empty() -> Form {
  Form("", "", False, None)
}

pub fn view(
  form: Form,
  on_email: fn(String) -> msg,
  on_password: fn(String) -> msg,
  on_submit: msg,
) -> Element(msg) {
  html.main([class("signin")], [
    html.h1([], [html.text("Atlas")]),
    html.p([class("muted")], [html.text("Sign in to see your training.")]),
    html.form([event.on_submit(fn(_) { on_submit })], [
      html.label([attribute.for("email")], [html.text("E-mail")]),
      html.input([
        class("form-control"),
        attribute.id("email"),
        attribute.type_("email"),
        attribute.name("email"),
        attribute.autocomplete("username"),
        attribute.value(form.email),
        attribute.required(True),
        event.on_input(on_email),
      ]),
      html.label([attribute.for("password")], [html.text("Password")]),
      html.input([
        class("form-control"),
        attribute.id("password"),
        attribute.type_("password"),
        attribute.name("password"),
        attribute.autocomplete("current-password"),
        attribute.value(form.password),
        attribute.required(True),
        event.on_input(on_password),
      ]),
      case form.error {
        Some(message) ->
          html.p([class("error"), attribute.role("alert")], [html.text(message)])
        None -> element.none()
      },
      html.button(
        [
          class("btn btn-primary"),
          attribute.type_("submit"),
          attribute.disabled(form.busy),
        ],
        [
          html.text(case form.busy {
            True -> "Signing in…"
            False -> "Sign in"
          }),
        ],
      ),
    ]),
  ])
}
