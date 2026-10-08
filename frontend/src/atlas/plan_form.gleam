//// The plan form: what the user typed, whether it is acceptable, and which fields to write.
//// Pure. The limits are those of the server (ADR 0009): a title of 1-200 characters and a description of up to 5000.
//// The phases and the weekly distance goal (ADR 0043) are a part of their own, `Settings`, which the plan's
//// sidebar edits on its own too.

import atlas/outbox
import atlas/plan.{type Intensity, type Phases, type Plan, Phases}
import atlas/workout_form
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const max_title = 200

pub const max_description = 5000

/// The server's limit for one phase.
pub const max_phase_weeks = 52

const max_goal_km = 1000.0

pub type Form {
  Form(
    title: String,
    description: String,
    visibility: plan.Visibility,
    settings: Settings,
    error: Option(String),
  )
}

/// The phase lengths in weeks and the weekly distance goal in km, as typed.
pub type Settings {
  Settings(
    base_weeks: String,
    pre_competition_weeks: String,
    competition_weeks: String,
    goal_km: String,
  )
}

/// Settings that passed `validate_settings`. A goal of 0 means "no goal".
pub type ValidSettings {
  ValidSettings(phases: Phases, weekly_distance_m: Float)
}

/// A form that passed `validate`: trimmed and within the limits.
pub type Valid {
  Valid(
    title: String,
    description: String,
    visibility: plan.Visibility,
    settings: ValidSettings,
  )
}

pub fn empty() -> Form {
  Form("", "", plan.Private, default_settings(), None)
}

/// 4 + 4 + 4 weeks and no goal.
pub fn default_settings() -> Settings {
  settings_of(plan.default_phases, None)
}

pub fn from_plan(plan: Plan) -> Form {
  Form(plan.title, plan.description, plan.visibility, settings_from(plan), None)
}

/// A plan without phases (made before they existed) is offered the default ones.
pub fn settings_from(plan: Plan) -> Settings {
  case plan.phase_weeks(plan.phases) {
    0 -> settings_of(plan.default_phases, plan.weekly_distance_m)
    _ -> settings_of(plan.phases, plan.weekly_distance_m)
  }
}

fn settings_of(phases: Phases, goal: Option(Float)) -> Settings {
  Settings(
    base_weeks: int.to_string(phases.base_weeks),
    pre_competition_weeks: int.to_string(phases.pre_competition_weeks),
    competition_weeks: int.to_string(phases.competition_weeks),
    goal_km: case goal {
      Some(m) -> workout_form.format_km(m)
      None -> ""
    },
  )
}

pub fn validate_settings(settings: Settings) -> Result(ValidSettings, String) {
  let weeks = fn(text, name) {
    case int.parse(string.trim(text)) {
      Ok(n) if n >= 0 && n <= max_phase_weeks -> Ok(n)
      _ ->
        Error(
          "The " <> name <> " phase must be a number of weeks from 0 to 52.",
        )
    }
  }
  let goal = case string.trim(settings.goal_km) {
    "" -> Ok(0.0)
    typed ->
      case workout_form.parse_decimal(typed) {
        Ok(km) if km <=. max_goal_km -> Ok(km *. 1000.0)
        Ok(_) -> Error("The weekly distance goal can be at most 1000 km.")
        Error(Nil) ->
          Error("Enter the weekly distance goal in kilometres, for example 40.")
      }
  }
  case
    weeks(settings.base_weeks, "base"),
    weeks(settings.pre_competition_weeks, "pre-competition"),
    weeks(settings.competition_weeks, "competition"),
    goal
  {
    Error(message), _, _, _
    | _, Error(message), _, _
    | _, _, Error(message), _
    | _, _, _, Error(message)
    -> Error(message)
    Ok(base), Ok(pre), Ok(competition), Ok(goal_m) -> {
      let phases = Phases(base, pre, competition)
      case plan.phase_weeks(phases) {
        0 -> Error("The plan needs at least one week.")
        n if n > workout_form.max_weeks ->
          Error("The phases can last at most 60 weeks together.")
        _ -> Ok(ValidSettings(phases, goal_m))
      }
    }
  }
}

pub fn visibility_from_string(text: String) -> plan.Visibility {
  case text {
    "public" -> plan.Public
    _ -> plan.Private
  }
}

pub fn validate(form: Form) -> Result(Valid, String) {
  let title = string.trim(form.title)
  let description = string.trim(form.description)
  case string.length(title), string.length(description) {
    0, _ -> Error("Give the plan a title.")
    n, _ if n > max_title -> Error("The title can have at most 200 characters.")
    _, n if n > max_description ->
      Error("The description can have at most 5000 characters.")
    _, _ ->
      case validate_settings(form.settings) {
        Ok(settings) -> Ok(Valid(title, description, form.visibility, settings))
        Error(message) -> Error(message)
      }
  }
}

/// The fields of a new plan. `owner_id` must be the signed-in user (the server checks it too).
pub fn create_fields(owner_id: String, valid: Valid) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("owner", owner_id),
    outbox.field_string("title", valid.title),
    outbox.field_string("description", valid.description),
    outbox.field_string(
      "visibility",
      plan.visibility_to_string(valid.visibility),
    ),
    ..all_settings_fields(valid.settings)
  ])
}

fn all_settings_fields(settings: ValidSettings) -> List(#(String, String)) {
  [
    outbox.field_int("base_weeks", settings.phases.base_weeks),
    outbox.field_int(
      "pre_competition_weeks",
      settings.phases.pre_competition_weeks,
    ),
    outbox.field_int("competition_weeks", settings.phases.competition_weeks),
    outbox.field_float("weekly_distance_m", settings.weekly_distance_m),
  ]
}

/// The phase and goal fields that differ from the plan as it is now. Empty when nothing changed.
pub fn changed_settings_fields(
  original: Plan,
  settings: ValidSettings,
) -> outbox.Fields {
  settings_changes(original, settings) |> dict.from_list
}

fn settings_changes(
  original: Plan,
  settings: ValidSettings,
) -> List(#(String, String)) {
  all_settings_fields(settings)
  |> list.filter(fn(field) {
    case field.0 {
      "base_weeks" -> settings.phases.base_weeks != original.phases.base_weeks
      "pre_competition_weeks" ->
        settings.phases.pre_competition_weeks
        != original.phases.pre_competition_weeks
      "competition_weeks" ->
        settings.phases.competition_weeks != original.phases.competition_weeks
      "weekly_distance_m" ->
        settings.weekly_distance_m
        != option.unwrap(original.weekly_distance_m, 0.0)
      _ -> False
    }
  })
}

/// The plan's week intensities with one week set to `level`, or cleared with `None`. Empty when that
/// is what the week has already.
pub fn intensity_fields(
  original: Plan,
  week: Int,
  level: Option(Intensity),
) -> outbox.Fields {
  let current = dict.get(original.week_intensity, week)
  case current, level {
    Error(Nil), None -> dict.new()
    Ok(now), Some(wanted) if now == wanted -> dict.new()
    _, _ -> {
      let updated = case level {
        Some(wanted) -> dict.insert(original.week_intensity, week, wanted)
        None -> dict.delete(original.week_intensity, week)
      }
      dict.from_list([#("week_intensity", encode_intensities(updated))])
    }
  }
}

/// `{"3":"high"}`, in week order so the same intensities always give the same text.
pub fn encode_intensities(intensities: dict.Dict(Int, Intensity)) -> String {
  intensities
  |> dict.to_list
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> list.map(fn(pair) {
    #(int.to_string(pair.0), json.string(plan.intensity_to_string(pair.1)))
  })
  |> json.object
  |> json.to_string
}

/// Only what differs from the plan as it is now, so an edit says exactly what the user changed.
/// Empty when nothing changed.
pub fn changed_fields(original: Plan, valid: Valid) -> outbox.Fields {
  [
    #(valid.title != original.title, outbox.field_string("title", valid.title)),
    #(
      valid.description != original.description,
      outbox.field_string("description", valid.description),
    ),
    #(
      valid.visibility != original.visibility,
      outbox.field_string(
        "visibility",
        plan.visibility_to_string(valid.visibility),
      ),
    ),
  ]
  |> list.filter(fn(item) { item.0 })
  |> list.map(fn(item) { item.1 })
  |> list.append(settings_changes(original, valid.settings))
  |> dict.from_list
}
