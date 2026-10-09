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
        Error(message) -> refused(model, message)
      }

    FillFromThresholdClicked ->
      case pace_zones.fill_from_threshold(model.pace) {
        Ok(form) -> edited(Model(..model, pace: form))
        Error(message) -> refused(model, message)
      }

    ResetClicked -> #(filled(model, me), effect.none(), [])

    SavedClosed -> #(Model(..model, saved: False), effect.none(), [])

    Submitted ->
      case parse(model) {
        Error(message) -> refused(model, message)
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

fn parse(model: Model) -> Result(athlete_settings.Zones, String) {
  use hr <- result.try(hr_zones.parse(model.hr))
  use lactate <- result.try(lactate_zones.parse(model.lactate))
  use pace <- result.try(pace_zones.parse(model.pace))
  Ok(athlete_settings.Zones(hr, lactate, pace))
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
    edited: False,
    saved: False,
  )
}

fn refused(
  model: Model,
  message: String,
) -> #(Model, Effect(Msg), List(Action)) {
  #(Model(..model, error: Some(message)), effect.none(), [])
}

fn edited(model: Model) -> #(Model, Effect(Msg), List(Action)) {
  #(Model(..model, error: None, edited: True, saved: False), effect.none(), [])
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
      html.div([class("row")], [
        field.text("hr-max", "Maximum heart rate", field.suffix("bpm"), [
          attribute.type_("text"),
          attribute.attribute("inputmode", "numeric"),
          attribute.name("max_hr"),
          attribute.value(model.hr.max_hr),
          event.on_input(MaxChanged),
        ]),
        button.tonal(
          [attribute.type_("button"), event.on_click(FillFromMaxClicked)],
          [html.text("Work out zones from maximum")],
        ),
      ]),
      html.p([class("muted")], [
        html.text(
          "Defaults: 50, 60, 70, 80 and 90 percent of the maximum ("
          <> int.to_string(hr_zones.default_max_hr)
          <> " bpm until you set yours).",
        ),
      ]),
      zones_view("hr-zone-", "numeric", model.hr.starts, hr_ends, fn(n, v) {
        HrStartChanged(n, v)
      }),
      layout.subheader("Blood lactate"),
      html.p([class("muted")], [
        html.text("In mmol/L. Defaults: 1.0, 1.5, 2.5, 4.0 and 6.0."),
      ]),
      zones_view(
        "lactate-zone-",
        "decimal",
        model.lactate,
        lactate_ends,
        fn(n, v) { LactateStartChanged(n, v) },
      ),
      layout.subheader("Pace"),
      html.div([class("row")], [
        field.text("pace-threshold", "Threshold pace", field.suffix("min/km"), [
          attribute.type_("text"),
          attribute.name("threshold_pace"),
          attribute.value(model.pace.threshold),
          attribute.placeholder("5:00"),
          event.on_input(ThresholdChanged),
        ]),
        button.tonal(
          [attribute.type_("button"), event.on_click(FillFromThresholdClicked)],
          [html.text("Work out zones from threshold pace")],
        ),
      ]),
      html.p([class("muted")], [
        html.text(
          "The pace you could hold for about an hour. Defaults: zones start at 140, 129, 114, 106 and 99 percent of its time per km ("
          <> pace_zones.format(pace_zones.default_threshold_s)
          <> " /km until you set yours).",
        ),
      ]),
      zones_view("pace-zone-", "text", model.pace.starts, pace_ends, fn(n, v) {
        PaceStartChanged(n, v)
      }),
      case model.error {
        Some(message) -> error.message(message)
        None -> element.none()
      },
      layout.actions([
        button.filled([attribute.type_("submit")], [html.text("Save zones")]),
        case model.edited {
          True ->
            button.outlined(
              [attribute.type_("button"), event.on_click(ResetClicked)],
              [html.text("Undo changes")],
            )
          False -> element.none()
        },
        case model.saved {
          True -> snackbar.view("Zones saved.", None, SavedClosed)
          False -> element.none()
        },
      ]),
    ]),
  ])
}

fn zones_view(
  id_prefix: String,
  input_mode: String,
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
          html.label([attribute.for(id)], [
            html.text("Zone " <> int.to_string(number) <> " from"),
          ]),
          field.input([
            attribute.id(id),
            attribute.type_("text"),
            attribute.attribute("inputmode", input_mode),
            attribute.value(pair.0),
            event.on_input(fn(value) { changed(number, value) }),
          ]),
          html.span([class("muted")], [html.text(pair.1)]),
        ])
      }),
  )
}
