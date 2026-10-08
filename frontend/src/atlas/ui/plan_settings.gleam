//// The inputs for a plan's phase lengths and weekly distance goal (ADR 0043), shared by the plan form and the
//// plan's sidebar. `prefix` keeps the IDs apart when both are on the page.

import atlas/plan_form.{type Settings}
import atlas/ui/field
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Messages(msg) {
  Messages(
    base_weeks: fn(String) -> msg,
    pre_competition_weeks: fn(String) -> msg,
    competition_weeks: fn(String) -> msg,
    goal_km: fn(String) -> msg,
  )
}

/// `error` is the form's problem, shown under the phases or the goal when `plan_form.settings_error_field` names
/// one of them (ADR 0059).
pub fn inputs(
  prefix: String,
  settings: Settings,
  messages: Messages(msg),
  error: Option(String),
) -> Element(msg) {
  let wrong = plan_form.settings_error_field(settings)
  html.fieldset([class("plan-settings")], [
    html.legend([], [html.text("Phases (weeks)")]),
    html.div([class("row")], [
      weeks(
        prefix <> "-base-weeks",
        "Base",
        settings.base_weeks,
        messages.base_weeks,
      ),
      weeks(
        prefix <> "-pre-competition-weeks",
        "Pre-competition",
        settings.pre_competition_weeks,
        messages.pre_competition_weeks,
      ),
      weeks(
        prefix <> "-competition-weeks",
        "Competition",
        settings.competition_weeks,
        messages.competition_weeks,
      ),
    ]),
    case wrong, error {
      "phases", Some(message) ->
        html.p(
          [class("md-field-supporting phases-error"), attribute.role("alert")],
          [
            html.text(message),
          ],
        )
      _, _ -> element.none()
    },
    field.text(
      prefix <> "-goal",
      "Weekly distance goal",
      field.with_error(field.Help("Optional", "km", None), "goal", wrong, error),
      [
        attribute.type_("text"),
        attribute.attribute("inputmode", "decimal"),
        attribute.name("weekly_distance"),
        attribute.value(settings.goal_km),
        event.on_input(messages.goal_km),
      ],
    ),
  ])
}

fn weeks(
  id: String,
  label: String,
  value: String,
  on_input: fn(String) -> msg,
) -> Element(msg) {
  field.text(id, label, field.plain, [
    attribute.type_("number"),
    attribute.attribute("min", "0"),
    attribute.attribute("max", "52"),
    attribute.value(value),
    event.on_input(on_input),
  ])
}
