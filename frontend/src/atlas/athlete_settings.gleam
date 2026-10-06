//// An athlete's settings row (ADR 0034, 0035, 0036): their heart-rate, lactate and pace zones. One row per athlete, whose ID
//// is the athlete's user ID. Pure: which row is whose, and the fields to write.

import atlas/hr_zones.{type HrZones}
import atlas/lactate_zones.{type LactateZones}
import atlas/outbox
import atlas/pace_zones.{type PaceZones}
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}

/// A stored row with the fields the screen needs.
pub type Row {
  Row(
    owner_id: String,
    hr: HrZones,
    lactate: LactateZones,
    pace: PaceZones,
    updated: String,
  )
}

/// The row of `me`. Coaches' devices also hold the rows of their athletes, so rows are searched by owner.
pub fn row_of(rows: List(Row), me: String) -> Option(Row) {
  case list.find(rows, fn(row) { row.owner_id == me }) {
    Ok(row) -> Some(row)
    Error(Nil) -> None
  }
}

/// All zones of an athlete.
pub type Zones {
  Zones(hr: HrZones, lactate: LactateZones, pace: PaceZones)
}

pub fn defaults() -> Zones {
  Zones(
    hr_zones.defaults(hr_zones.default_max_hr),
    lactate_zones.defaults(),
    pace_zones.defaults(pace_zones.default_threshold_s),
  )
}

/// The zones that apply to `me`: their saved ones, or the defaults.
pub fn current(rows: List(Row), me: String) -> Zones {
  case row_of(rows, me) {
    Some(row) -> Zones(row.hr, row.lactate, row.pace)
    None -> defaults()
  }
}

/// The fields to write: the owner and every value, so the stored row is always complete.
pub fn fields(owner: String, zones: Zones) -> outbox.Fields {
  let hr_starts =
    list.index_map(zones.hr.starts, fn(start, index) {
      outbox.field_int(hr_zones.start_field(index + 1), start)
    })
  let lactate_starts =
    list.index_map(zones.lactate.starts, fn(start, index) {
      outbox.field_float(
        lactate_zones.start_field(index + 1),
        lactate_zones.to_mmol(start),
      )
    })
  let pace_starts =
    list.index_map(zones.pace.starts, fn(start, index) {
      outbox.field_int(pace_zones.start_field(index + 1), start)
    })
  dict.from_list([
    outbox.field_string("owner", owner),
    outbox.field_int("max_hr", zones.hr.max_hr),
    outbox.field_int(pace_zones.threshold_field, zones.pace.threshold_s),
    ..list.flatten([hr_starts, lactate_starts, pace_starts])
  ])
}
