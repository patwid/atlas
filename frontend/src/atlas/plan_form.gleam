//// The plan form: what the user typed, whether it is acceptable, and which fields to write.
//// Pure. The limits are those of the server (ADR 0009): a title of 1-200 characters and a description of up to 5000.
//// The phases and the weekly distance goal (ADR 0043) are a part of their own, `Settings`, which the plan's
//// sidebar edits on its own too. A new plan needs a start date, which can be changed but not removed (ADR 0108), and
//// is for one athlete, chosen when it is made (ADR 0110).

import atlas/date.{type Date}
import atlas/outbox
import atlas/plan.{type Phases, type Plan, Phases}
import atlas/workout_form
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
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
    /// Who a new plan is for: the user, or an athlete who granted them access (ADR 0110). Fixed once it is made.
    athlete_id: String,
    /// As typed or picked: `YYYY-MM-DD`.
    start_date: String,
    /// False only for a plan that has no start date yet (made before ADR 0108): it may stay without one.
    start_required: Bool,
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
    start_date: Option(Date),
    settings: ValidSettings,
  )
}

/// A new plan is for the user and starts on the coming Monday unless chosen otherwise.
pub fn empty(today: Date, user_id: String) -> Form {
  Form(
    "",
    "",
    user_id,
    date.to_string(plan.coming_monday(today)),
    True,
    default_settings(),
    None,
  )
}

/// 4 + 4 + 4 weeks and no goal.
pub fn default_settings() -> Settings {
  settings_of(plan.default_phases, None)
}

/// Editing a plan; its athlete is not changed.
pub fn from_plan(plan: Plan) -> Form {
  Form(
    plan.title,
    plan.description,
    "",
    case plan.start_date {
      Some(start) -> date.to_string(start)
      None -> ""
    },
    plan.start_date != None,
    settings_from(plan),
    None,
  )
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

/// Checks the phases and goal; a problem names the field it is about: `phases` or `goal` (ADR 0059).
pub fn validate_settings_fields(
  settings: Settings,
) -> Result(ValidSettings, #(String, String)) {
  let weeks = fn(text, name) {
    case int.parse(string.trim(text)) {
      Ok(n) if n >= 0 && n <= max_phase_weeks -> Ok(n)
      _ ->
        Error(#(
          "phases",
          "The " <> name <> " phase must be a number of weeks from 0 to 52.",
        ))
    }
  }
  let goal = case string.trim(settings.goal_km) {
    "" -> Ok(0.0)
    typed ->
      case workout_form.parse_decimal(typed) {
        Ok(km) if km <=. max_goal_km -> Ok(km *. 1000.0)
        Ok(_) ->
          Error(#("goal", "The weekly distance goal can be at most 1000 km."))
        Error(Nil) ->
          Error(#(
            "goal",
            "Enter the weekly distance goal in kilometres, for example 40.",
          ))
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
        0 -> Error(#("phases", "The plan needs at least one week."))
        n if n > workout_form.max_weeks ->
          Error(#("phases", "The phases can last at most 60 weeks together."))
        _ -> Ok(ValidSettings(phases, goal_m))
      }
    }
  }
}

/// The start date as typed: none only where it may be left out; years outside 2000-2100 are typing mistakes.
fn validate_start(form: Form) -> Result(Option(Date), #(String, String)) {
  case string.trim(form.start_date), form.start_required {
    "", False -> Ok(None)
    "", True -> Error(#("start", "Pick the plan's first day."))
    typed, _ ->
      case date.parse(typed) {
        Ok(start) if start.year >= 2000 && start.year <= 2100 -> Ok(Some(start))
        Ok(_) ->
          Error(#(
            "start",
            "The start date must be between the years 2000 and 2100.",
          ))
        Error(Nil) -> Error(#("start", "Pick the plan's first day."))
      }
  }
}

/// Checks the form; a problem names the field it is about: `title`, `description`, `start`, `phases` or `goal`.
pub fn validate_fields(form: Form) -> Result(Valid, #(String, String)) {
  let title = string.trim(form.title)
  let description = string.trim(form.description)
  case string.length(title), string.length(description) {
    0, _ -> Error(#("title", "Give the plan a title."))
    n, _ if n > max_title ->
      Error(#("title", "The title can have at most 200 characters."))
    _, n if n > max_description ->
      Error(#(
        "description",
        "The description can have at most 5000 characters.",
      ))
    _, _ ->
      case validate_start(form), validate_settings_fields(form.settings) {
        Error(problem), _ | _, Error(problem) -> Error(problem)
        Ok(start), Ok(settings) ->
          Ok(Valid(title, description, start, settings))
      }
  }
}

/// The fields of a new plan. `owner_id` must be the signed-in user (the server checks it too).
pub fn create_fields(owner_id: String, valid: Valid) -> outbox.Fields {
  dict.from_list([
    outbox.field_string("owner", owner_id),
    outbox.field_string("title", valid.title),
    outbox.field_string("description", valid.description),
    outbox.field_string("start_date", start_text(valid.start_date)),
    ..all_settings_fields(valid.settings)
  ])
}

fn start_text(start: Option(Date)) -> String {
  case start {
    Some(day) -> date.to_string(day)
    None -> ""
  }
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

/// The plan's week intensities with one week set to `level` (0.0 to 1.0, kept to whole percent), or cleared
/// with `None`. Empty when that is what the week has already.
pub fn intensity_fields(
  original: Plan,
  week: Int,
  level: Option(Float),
) -> outbox.Fields {
  let current = dict.get(original.week_intensity, week)
  let level = option.map(level, plan.intensity)
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

/// One intensity per week up to the last one set, `null` for a week without one: `[null,0.8]`.
pub fn encode_intensities(intensities: dict.Dict(Int, Float)) -> String {
  let last =
    dict.fold(intensities, 0, fn(highest, week, _) { int.max(highest, week) })
  list.repeat(Nil, last)
  |> list.index_map(fn(_, index) {
    case dict.get(intensities, index + 1) {
      Ok(level) -> json.float(level)
      Error(Nil) -> json.null()
    }
  })
  |> json.preprocessed_array
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
      valid.start_date != original.start_date,
      outbox.field_string("start_date", start_text(valid.start_date)),
    ),
  ]
  |> list.filter(fn(item) { item.0 })
  |> list.map(fn(item) { item.1 })
  |> list.append(settings_changes(original, valid.settings))
  |> dict.from_list
}

/// The form's problem without the field it is about (ADR 0059).
pub fn validate(form: Form) -> Result(Valid, String) {
  validate_fields(form) |> result.map_error(fn(problem) { problem.1 })
}

/// The field the form's problem is about, `""` when there is none: its error is shown under that field (ADR 0059).
pub fn error_field(form: Form) -> String {
  case validate_fields(form) {
    Error(#(field, _)) -> field
    Ok(_) -> ""
  }
}

pub fn validate_settings(settings: Settings) -> Result(ValidSettings, String) {
  validate_settings_fields(settings)
  |> result.map_error(fn(problem) { problem.1 })
}

/// The field of the phases-and-goal problem, `""` when there is none (ADR 0059).
pub fn settings_error_field(settings: Settings) -> String {
  case validate_settings_fields(settings) {
    Error(#(field, _)) -> field
    Ok(_) -> ""
  }
}
