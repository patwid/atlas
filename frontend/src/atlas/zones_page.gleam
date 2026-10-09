//// Training zones, in Settings (ADR 0034, 0035, 0036): the maximum heart rate and where each heart-rate zone
//// starts, where each lactate zone starts, and the threshold pace and where each pace zone starts. The form is filled with the saved zones, or with the defaults until the
//// athlete saves their own. One row per athlete, whose ID is the athlete's user ID, so devices that save offline
//// write to the same row. Own state and messages; writes come back as `Action`s.

import atlas/athlete_settings
import atlas/collection
import atlas/hr_zones
import atlas/lactate_zones
import atlas/outbox
import atlas/pace_zones
import atlas/records
import atlas/store
import atlas/ui/button
import atlas/ui/error
import atlas/ui/field
import atlas/ui/focus
import atlas/ui/layout
import atlas/ui/progress
import atlas/ui/snackbar
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model(
    rows: List(athlete_settings.Row),
    loaded: Bool,
    hr: hr_zones.Form,
    /// The text of the five lactate zone starts.
    lactate: List(String),
    pace: pace_zones.Form,
    error: Option(String),
    /// The ID of the input the error is about, or "" for the whole form (ADR 0077).
    error_field: String,
    /// The user changed the form since it was filled, so synced changes do not overwrite it.
    edited: Bool,
    saved: Bool,
  )
}

pub type Msg {
  Refresh
  RowsRead(Result(List(Dynamic), Nil))
  MaxChanged(String)
  HrStartChanged(zone: Int, value: String)
  LactateStartChanged(zone: Int, value: String)
  ThresholdChanged(String)
  PaceStartChanged(zone: Int, value: String)
  FillFromMaxClicked
  FillFromThresholdClicked
  ResetClicked
  Submitted
  /// The "Saved." snackbar was closed (ADR 0047).
  SavedClosed
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
}

pub fn new() -> Model {
  filled(
    Model(
      [],
      False,
      hr_zones.Form("", []),
      [],
      pace_zones.Form("", []),
      None,
      "",
      False,
      False,
    ),
    "",
  )
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.AthleteSettings, fn(result) {
      dispatch(RowsRead(result))
    })
  })
}

/// The zones that apply to `me`: their saved ones, or the defaults.
pub fn current(model: Model, me: String) -> athlete_settings.Zones {
  athlete_settings.current(model.rows, me)
}

/// `me` is the signed-in user: the owner, and the ID, of their row.
pub fn update(
  model: Model,
  msg: Msg,
  me: String,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    RowsRead(Ok(stored)) -> {
      let model =
        Model(
          ..model,
          rows: records.live(stored, records.athlete_settings_row),
          loaded: True,
        )
      case model.edited {
        True -> #(model, effect.none(), [])
        False -> #(filled(model, me), effect.none(), [])
      }
    }
    RowsRead(Error(Nil)) -> #(model, effect.none(), [])

    MaxChanged(value) ->
      edited(Model(..model, hr: hr_zones.Form(..model.hr, max_hr: value)))

    HrStartChanged(zone, value) ->
      edited(
        Model(
          ..model,
          hr: hr_zones.Form(
            ..model.hr,
            starts: replace_at(model.hr.starts, zone, value),
          ),
        ),
      )

    LactateStartChanged(zone, value) ->
      edited(Model(..model, lactate: replace_at(model.lactate, zone, value)))

    ThresholdChanged(value) ->
      edited(
        Model(..model, pace: pace_zones.Form(..model.pace, threshold: value)),
      )

    PaceStartChanged(zone, value) ->
      edited(
        Model(
          ..model,
          pace: pace_zones.Form(
            ..model.pace,
            starts: replace_at(model.pace.starts, zone, value),
          ),
        ),
      )

    FillFromMaxClicked ->
      case hr_zones.fill_from_max(model.hr) {
        Ok(form) -> edited(Model(..model, hr: form))
        Error(message) -> refused(model, "hr-max", message)
      }

    FillFromThresholdClicked ->
      case pace_zones.fill_from_threshold(model.pace) {
        Ok(form) -> edited(Model(..model, pace: form))
        Error(message) -> refused(model, "pace-threshold", message)
      }

    ResetClicked -> #(filled(model, me), effect.none(), [])

    SavedClosed -> #(Model(..model, saved: False), effect.none(), [])

    Submitted ->
      case parse(model) {
        Error(#(field, message)) -> refused(model, field, message)
        Ok(zones) -> {
          let fields = athlete_settings.fields(me, zones)
          let action = case athlete_settings.row_of(model.rows, me) {
            Some(row) -> Edit(me, fields, row.updated)
            None -> Create(me, fields)
          }
          #(Model(..with_zones(model, zones), saved: True), effect.none(), [
            action,
          ])
        }
      }
  }
}

/// The zones, or the ID of the input that is wrong ("" for none in particular) and what is wrong with it.
fn parse(model: Model) -> Result(athlete_settings.Zones, #(String, String)) {
  use hr <- result.try(
    hr_zones.parse_at(model.hr) |> result.map_error(input("hr-max", "hr-zone-")),
  )
  use lactate <- result.try(
    lactate_zones.parse_at(model.lactate)
    |> result.map_error(input("", "lactate-zone-")),
  )
  use pace <- result.try(
    pace_zones.parse_at(model.pace)
    |> result.map_error(input("pace-threshold", "pace-zone-")),
  )
  Ok(athlete_settings.Zones(hr, lactate, pace))
}

/// The input's ID for a zone module's problem: 0 is `first`, 1 to 5 a zone's start, anything else none.
fn input(
  first: String,
  zone_prefix: String,
) -> fn(#(Int, String)) -> #(String, String) {
  fn(problem) {
    let #(number, message) = problem
    case number {
      0 -> #(first, message)
      n if n >= 1 && n <= 5 -> #(zone_prefix <> int.to_string(n), message)
      _ -> #("", message)
    }
  }
}

/// The form filled with the zones that apply to `me`, as saved.
fn filled(model: Model, me: String) -> Model {
  with_zones(model, current(model, me))
}

fn with_zones(model: Model, zones: athlete_settings.Zones) -> Model {
  Model(
    ..model,
    hr: hr_zones.to_form(zones.hr),
    lactate: lactate_zones.to_form(zones.lactate),
    pace: pace_zones.to_form(zones.pace),
    error: None,
    error_field: "",
    edited: False,
    saved: False,
  )
}

/// The problem shows under its input, which gets the focus so that it is in view (ADR 0059, 0077).
fn refused(
  model: Model,
  field: String,
  message: String,
) -> #(Model, Effect(Msg), List(Action)) {
  #(
    Model(..model, error: Some(message), error_field: field),
    case field {
      "" -> effect.none()
      id -> focus.soon(id)
    },
    [],
  )
}

fn edited(model: Model) -> #(Model, Effect(Msg), List(Action)) {
  #(
    Model(..model, error: None, error_field: "", edited: True, saved: False),
    effect.none(),
    [],
  )
}

fn replace_at(values: List(String), zone: Int, value: String) -> List(String) {
  list.index_map(values, fn(old, index) {
    case index + 1 == zone {
      True -> value
      False -> old
    }
  })
}

// VIEWS -------------------------------------------------------------------------------------------

pub fn view(model: Model, me: String) -> Element(Msg) {
  case model.loaded {
    True -> form_view(model, me)
    // Not the form with the defaults: an edit made before the saved zones arrive would keep them from filling in,
    // and saving would put the defaults over them.
    False -> progress.loading("Loading…")
  }
}

fn form_view(model: Model, me: String) -> Element(Msg) {
  // The end of each zone follows from the next one's start, so it is shown once that part is valid.
  let hr_ends = case hr_zones.parse(model.hr) {
    Ok(zones) ->
      list.map(hr_zones.zones(zones), fn(zone) {
        "to " <> int.to_string(zone.high) <> " bpm"
      })
    Error(_) -> list.map(model.hr.starts, fn(_) { "" })
  }
  let lactate_ends = case lactate_zones.parse(model.lactate) {
    Ok(zones) ->
      list.map(lactate_zones.zones(zones), fn(zone) {
        case zone.high {
          Some(high) -> "to " <> lactate_zones.format(high) <> " mmol/L"
          None -> "mmol/L and above"
        }
      })
    Error(_) -> list.map(model.lactate, fn(_) { "" })
  }
  let pace_ends = case pace_zones.parse(model.pace) {
    Ok(zones) ->
      list.map(pace_zones.zones(zones), fn(zone) {
        case zone.fastest {
          Some(fastest) -> "to " <> pace_zones.format(fastest) <> " /km"
          None -> "/km and faster"
        }
      })
    Error(_) -> list.map(model.pace.starts, fn(_) { "" })
  }
  html.section([class("training-zones")], [
    html.p([class("muted")], [
      html.text(case model.loaded, athlete_settings.row_of(model.rows, me) {
        True, None ->
          "These are the default zones. Change them to match yours and save."
        _, _ -> "Where each zone starts."
      }),
    ]),
    html.form([class("zones-form"), event.on_submit(fn(_) { Submitted })], [
      layout.subheader("Heart rate"),
      html.div([class("zone-source")], [
        field.text(
          "hr-max",
          "Maximum heart rate",
          on(
            model,
            field.Help(
              "Zones start at 50 to 90% of it ("
                <> int.to_string(hr_zones.default_max_hr)
                <> " bpm until you set yours)",
              "bpm",
              None,
            ),
            "hr-max",
          ),
          [
            attribute.type_("text"),
            attribute.attribute("inputmode", "numeric"),
            attribute.name("max_hr"),
            attribute.value(model.hr.max_hr),
            event.on_input(MaxChanged),
          ],
        ),
        button.tonal(
          [attribute.type_("button"), event.on_click(FillFromMaxClicked)],
          [html.text("Calculate heart rate zones")],
        ),
      ]),
      zones_view(
        model,
        "hr-zone-",
        "numeric",
        "bpm",
        model.hr.starts,
        hr_ends,
        fn(n, v) { HrStartChanged(n, v) },
      ),
      layout.subheader("Blood lactate"),
      html.p([class("muted")], [
        html.text("Defaults: 1.0, 1.5, 2.5, 4.0 and 6.0 mmol/L."),
      ]),
      zones_view(
        model,
        "lactate-zone-",
        "decimal",
        "mmol/L",
        model.lactate,
        lactate_ends,
        fn(n, v) { LactateStartChanged(n, v) },
      ),
      layout.subheader("Pace"),
      html.div([class("zone-source")], [
        field.text(
          "pace-threshold",
          "Threshold pace",
          on(
            model,
            field.Help(
              "What you could hold for an hour, as m:ss ("
                <> pace_zones.format(pace_zones.default_threshold_s)
                <> " until you set yours)",
              "/km",
              None,
            ),
            "pace-threshold",
          ),
          [
            attribute.type_("text"),
            attribute.name("threshold_pace"),
            attribute.value(model.pace.threshold),
            event.on_input(ThresholdChanged),
          ],
        ),
        button.tonal(
          [attribute.type_("button"), event.on_click(FillFromThresholdClicked)],
          [html.text("Calculate pace zones")],
        ),
      ]),
      zones_view(
        model,
        "pace-zone-",
        "text",
        "/km",
        model.pace.starts,
        pace_ends,
        fn(n, v) { PaceStartChanged(n, v) },
      ),
      // A problem with no input of its own shows by the buttons.
      case model.error, model.error_field {
        Some(message), "" -> error.message(message)
        _, _ -> element.none()
      },
      // The buttons stay in view at the bottom while the long form scrolls (ADR 0077).
      layout.actions([
        button.filled([attribute.type_("submit")], [html.text("Save zones")]),
        button.outlined(
          [
            attribute.type_("button"),
            attribute.disabled(!model.edited),
            event.on_click(ResetClicked),
          ],
          [html.text("Discard changes")],
        ),
        case model.saved {
          True -> snackbar.view("Zones saved.", None, SavedClosed)
          False -> element.none()
        },
      ]),
    ]),
  ])
}

/// The help for input `id`, with the form's problem when it is about that input.
fn on(model: Model, help: field.Help, id: String) -> field.Help {
  field.with_error(help, id, model.error_field, model.error)
}

/// One outlined field per zone, with its unit, and where the zone ends beside it.
fn zones_view(
  model: Model,
  id_prefix: String,
  input_mode: String,
  unit: String,
  starts: List(String),
  ends: List(String),
  changed: fn(Int, String) -> Msg,
) -> Element(Msg) {
  html.div(
    [class("zones")],
    list.zip(starts, ends)
      |> list.index_map(fn(pair, index) {
        let number = index + 1
        let id = id_prefix <> int.to_string(number)
        html.div([class("zone")], [
          field.text(
            id,
            "Zone " <> int.to_string(number) <> " from",
            on(model, field.suffix(unit), id),
            [
              attribute.type_("text"),
              attribute.attribute("inputmode", input_mode),
              attribute.value(pair.0),
              event.on_input(fn(value) { changed(number, value) }),
            ],
          ),
          html.span([class("zone-end")], [html.text(pair.1)]),
        ])
      }),
  )
}
