//// The sign-in page. Messages are passed in so this module does not depend on the app's `Msg`.

import atlas/auth
import atlas/ui/button
import atlas/ui/field
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
  // A wrong or missing e-mail or password marks both fields, and they point to the message; a connection problem
  // is not about them.
  let marked = case form.error {
    Some(message) ->
      message == auth.wrong_credentials || message == auth.missing_credentials
    None -> False
  }
  let invalid = case marked {
    True -> [
      attribute.attribute("aria-invalid", "true"),
      attribute.attribute("aria-describedby", "signin-error"),
    ]
    False -> []
  }
  html.main([class("signin")], [
    html.h1([], [html.text("Atlas")]),
    html.p([class("muted")], [html.text("Sign in to see your training.")]),
    html.form([event.on_submit(fn(_) { on_submit })], [
      field.text("email", "E-mail", field.plain, [
        attribute.type_("email"),
        attribute.name("email"),
        attribute.autocomplete("username"),
        attribute.value(form.email),
        attribute.required(True),
        event.on_input(on_email),
        ..invalid
      ]),
      field.text("password", "Password", field.plain, [
        attribute.type_("password"),
        attribute.name("password"),
        attribute.autocomplete("current-password"),
        attribute.value(form.password),
        attribute.required(True),
        event.on_input(on_password),
        ..invalid
      ]),
      case form.error {
        Some(message) ->
          html.p(
            [
              class("error"),
              attribute.role("alert"),
              attribute.id("signin-error"),
            ],
            [html.text(message)],
          )
        None -> element.none()
      },
      button.filled(
        [
          attribute.type_("submit"),
          attribute.disabled(form.busy),
          button.medium(),
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
