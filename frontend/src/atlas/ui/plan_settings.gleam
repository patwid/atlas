//// The inputs for a plan's phase lengths and weekly distance goal (ADR 0043), shared by the plan form and the
//// plan's sidebar. `prefix` keeps the IDs apart when both are on the page.

import atlas/plan_form.{type Settings}
import atlas/ui/field
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

pub fn inputs(
  prefix: String,
  settings: Settings,
  messages: Messages(msg),
) -> Element(msg) {
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
    html.label([attribute.for(prefix <> "-goal")], [
      html.text("Weekly distance goal (km)"),
    ]),
    field.input([
      attribute.id(prefix <> "-goal"),
      attribute.type_("text"),
      attribute.attribute("inputmode", "decimal"),
      attribute.name("weekly_distance"),
      attribute.value(settings.goal_km),
      attribute.placeholder("40"),
      event.on_input(messages.goal_km),
    ]),
  ])
}

fn weeks(
  id: String,
  label: String,
  value: String,
  on_input: fn(String) -> msg,
) -> Element(msg) {
  html.div([], [
    html.label([attribute.for(id)], [html.text(label)]),
    field.input([
      attribute.id(id),
      attribute.type_("number"),
      attribute.attribute("min", "0"),
      attribute.attribute("max", "52"),
      attribute.value(value),
      event.on_input(on_input),
    ]),
  ])
}
