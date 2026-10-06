//// Heart-rate zones, in Settings (ADR 0034): the maximum heart rate and where each zone starts. The form
//// is filled with the saved zones, or with the defaults until the athlete saves their own. One row per
//// athlete, whose ID is the athlete's user ID, so devices that save offline write to the same row.
//// Own state and messages; writes come back as `Action`s.

import atlas/collection
import atlas/hr_zones.{type Form, type HrZones, Form}
import atlas/outbox
import atlas/records
import atlas/store
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model(
    rows: List(hr_zones.Row),
    loaded: Bool,
    form: Form,
    /// The user changed the form since it was filled, so synced changes do not overwrite it.
    edited: Bool,
    saved: Bool,
  )
}

pub type Msg {
  Refresh
  RowsRead(Result(List(Dynamic), Nil))
  MaxChanged(String)
  StartChanged(zone: Int, value: String)
  FillFromMaxClicked
  ResetClicked
  Submitted
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
}

pub fn new() -> Model {
  Model(
    [],
    False,
    hr_zones.to_form(hr_zones.defaults(hr_zones.default_max_hr)),
    False,
    False,
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
pub fn current(model: Model, me: String) -> HrZones {
  case hr_zones.row_of(model.rows, me) {
    Some(row) -> row.zones
    None -> hr_zones.defaults(hr_zones.default_max_hr)
  }
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
          rows: records.live(stored, records.hr_zones_row),
          loaded: True,
        )
      case model.edited {
        True -> #(model, effect.none(), [])
        False -> #(
          Model(..model, form: hr_zones.to_form(current(model, me))),
          effect.none(),
          [],
        )
      }
    }
    RowsRead(Error(Nil)) -> #(model, effect.none(), [])

    MaxChanged(value) ->
      edit_form(model, Form(..model.form, max_hr: value, error: None))

    StartChanged(zone, value) ->
      edit_form(
        model,
        Form(
          ..model.form,
          starts: list.index_map(model.form.starts, fn(old, index) {
            case index + 1 == zone {
              True -> value
              False -> old
            }
          }),
          error: None,
        ),
      )

    FillFromMaxClicked -> edit_form(model, hr_zones.fill_from_max(model.form))

    ResetClicked -> #(
      Model(
        ..model,
        form: hr_zones.to_form(current(model, me)),
        edited: False,
        saved: False,
      ),
      effect.none(),
      [],
    )

    Submitted ->
      case hr_zones.parse(model.form) {
        Error(message) -> #(
          Model(..model, form: Form(..model.form, error: Some(message))),
          effect.none(),
          [],
        )
        Ok(zones) -> {
          let fields = hr_zones.fields(me, zones)
          let action = case hr_zones.row_of(model.rows, me) {
            Some(row) -> Edit(me, fields, row.updated)
            None -> Create(me, fields)
          }
          #(
            Model(
              ..model,
              form: hr_zones.to_form(zones),
              edited: False,
              saved: True,
            ),
            effect.none(),
            [action],
          )
        }
      }
  }
}

fn edit_form(model: Model, form: Form) -> #(Model, Effect(Msg), List(Action)) {
  #(Model(..model, form: form, edited: True, saved: False), effect.none(), [])
}

// VIEWS -------------------------------------------------------------------------------------------

pub fn view(model: Model, me: String) -> Element(Msg) {
  let form = model.form
  // The end of each zone follows from the next one's start, so it is shown once the form is valid.
  let ends = case hr_zones.parse(form) {
    Ok(zones) -> list.map(hr_zones.zones(zones), fn(zone) { Some(zone.high) })
    Error(_) -> list.map(form.starts, fn(_) { None })
  }
  html.section([class("hr-zones")], [
    html.h2([], [html.text("Heart-rate zones")]),
    html.p([class("muted")], [
      html.text(case model.loaded, hr_zones.row_of(model.rows, me) {
        True, None ->
          "These are the default zones (50, 60, 70, 80 and 90 percent of a maximum of "
          <> int.to_string(hr_zones.default_max_hr)
          <> "). Change them to match yours and save."
        _, _ -> "Where each zone starts, in beats per minute."
      }),
    ]),
    html.form([class("zones-form"), event.on_submit(fn(_) { Submitted })], [
      html.label([attribute.for("hr-max")], [
        html.text("Maximum heart rate (bpm)"),
      ]),
      html.div([class("row")], [
        html.input([
          attribute.id("hr-max"),
          attribute.type_("text"),
          attribute.attribute("inputmode", "numeric"),
          attribute.name("max_hr"),
          attribute.value(form.max_hr),
          event.on_input(MaxChanged),
        ]),
        html.button(
          [
            attribute.type_("button"),
            class("secondary"),
            event.on_click(FillFromMaxClicked),
          ],
          [html.text("Work out zones from maximum")],
        ),
      ]),
      html.div(
        [class("zones")],
        list.zip(form.starts, ends)
          |> list.index_map(fn(pair, index) {
            zone_view(index + 1, pair.0, pair.1)
          }),
      ),
      case form.error {
        Some(message) ->
          html.p([class("error"), attribute.role("alert")], [
            html.text(message),
          ])
        None -> element.none()
      },
      html.div([class("actions")], [
        html.button([attribute.type_("submit")], [html.text("Save zones")]),
        case model.edited {
          True ->
            html.button(
              [
                attribute.type_("button"),
                class("secondary"),
                event.on_click(ResetClicked),
              ],
              [html.text("Undo changes")],
            )
          False -> element.none()
        },
        case model.saved {
          True ->
            html.span([class("muted"), attribute.role("status")], [
              html.text("Saved."),
            ])
          False -> element.none()
        },
      ]),
    ]),
  ])
}

fn zone_view(
  number: Int,
  start: String,
  end: option.Option(Int),
) -> Element(Msg) {
  let id = "hr-zone-" <> int.to_string(number)
  html.div([class("zone")], [
    html.label([attribute.for(id)], [
      html.text("Zone " <> int.to_string(number) <> " from"),
    ]),
    html.input([
      attribute.id(id),
      attribute.type_("text"),
      attribute.attribute("inputmode", "numeric"),
      attribute.name(hr_zones.start_field(number)),
      attribute.value(start),
      event.on_input(fn(value) { StartChanged(number, value) }),
    ]),
    html.span([class("muted")], [
      html.text(case end {
        Some(high) -> "to " <> int.to_string(high) <> " bpm"
        None -> ""
      }),
    ]),
  ])
}
