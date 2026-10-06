//// An athlete's settings row (ADR 0034, 0035): their heart-rate and lactate zones. One row per athlete, whose ID
//// is the athlete's user ID. Pure: which row is whose, and the fields to write.

import atlas/hr_zones.{type HrZones}
import atlas/lactate_zones.{type LactateZones}
import atlas/outbox
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}

/// A stored row with the fields the screen needs.
pub type Row {
  Row(owner_id: String, hr: HrZones, lactate: LactateZones, updated: String)
}

/// The row of `me`. Coaches' devices also hold the rows of their athletes, so rows are searched by owner.
pub fn row_of(rows: List(Row), me: String) -> Option(Row) {
  case list.find(rows, fn(row) { row.owner_id == me }) {
    Ok(row) -> Some(row)
    Error(Nil) -> None
  }
}

/// The zones that apply to `me`: their saved ones, or the defaults.
pub fn current(rows: List(Row), me: String) -> #(HrZones, LactateZones) {
  case row_of(rows, me) {
    Some(row) -> #(row.hr, row.lactate)
    None -> #(
      hr_zones.defaults(hr_zones.default_max_hr),
      lactate_zones.defaults(),
    )
  }
}

/// The fields to write: the owner and every value, so the stored row is always complete.
pub fn fields(
  owner: String,
  hr: HrZones,
  lactate: LactateZones,
) -> outbox.Fields {
  let hr_starts =
    list.index_map(hr.starts, fn(start, index) {
      outbox.field_int(hr_zones.start_field(index + 1), start)
    })
  let lactate_starts =
    list.index_map(lactate.starts, fn(start, index) {
      outbox.field_float(
        lactate_zones.start_field(index + 1),
        lactate_zones.to_mmol(start),
      )
    })
  dict.from_list([
    outbox.field_string("owner", owner),
    outbox.field_int("max_hr", hr.max_hr),
    ..list.append(hr_starts, lactate_starts)
  ])
}
