//// An activity from a FIT file: the activity form filled in from the file, and the fields to write once the user
//// saves it. Pure. What the user did not change is written as the file says it, to the second and the
//// centimetre, and the file's laps, elapsed time and maximum heart rate come along (ADR 0100).

import atlas/activity
import atlas/activity_form.{type Form, type Row, type Valid}
import atlas/date
import atlas/fit.{type Lap, type Summary}
import atlas/outbox
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Import {
  Import(
    summary: Summary,
    file_name: String,
    /// The form as the file filled it in, to tell what the user changed afterwards.
    filled: Form,
  )
}

/// The start as PocketBase stores it.
pub fn started_at(summary: Summary) -> String {
  date.timestamp_from_unix(summary.started_at)
}

/// The import of a decoded file. `offset` is the UTC offset in minutes at its start, on this device.
pub fn new(summary: Summary, file_name: String, offset: Int) -> Import {
  let row =
    activity_form.Row(
      activity: activity.Activity(
        id: "",
        source: activity.Fit,
        started_at: started_at(summary),
        sport: summary.sport,
        distance_m: summary.distance_m,
        moving_time_s: summary.moving_time_s,
      ),
      owner_id: "",
      name: "",
      elevation_m: case summary.elevation_gain_m {
        Some(m) -> int.to_float(m)
        None -> 0.0
      },
      avg_hr: option.unwrap(summary.avg_hr, 0),
      updated: "",
      external_id: summary.file_id,
    )
  Import(summary, file_name, activity_form.from_row(row, offset))
}

/// The user's own activity imported from the same file, if there is one.
pub fn already_imported(
  rows: List(Row),
  user_id: String,
  summary: Summary,
) -> Option(Row) {
  list.find(rows, fn(row) {
    row.owner_id == user_id
    && row.activity.source == activity.Fit
    && row.external_id == summary.file_id
  })
  |> option.from_result
}

/// The fields of a new activity from the file. `offset` is the UTC offset in minutes at the form's day and time.
pub fn create_fields(
  owner_id: String,
  imported: Import,
  valid: Valid,
  offset: Int,
) -> outbox.Fields {
  activity_form.create_fields(owner_id, valid, offset)
  |> dict.merge(dict.from_list(file_fields(imported, valid)))
}

/// The fields that bring back an earlier import of the same file that was deleted: the server keeps one row per
/// file (its unique `external_id`), so the deleted row is changed rather than a second one made.
pub fn revive_fields(
  imported: Import,
  valid: Valid,
  offset: Int,
) -> outbox.Fields {
  create_fields("", imported, valid, offset)
  |> dict.drop(["owner", "source"])
  |> dict.merge(dict.from_list([outbox.field_bool("deleted", False)]))
}

fn file_fields(imported: Import, valid: Valid) -> List(#(String, String)) {
  let summary = imported.summary
  let unchanged = case activity_form.validate(imported.filled) {
    Ok(filled) -> Some(filled)
    Error(_) -> None
  }
  let same = fn(changed: fn(Valid) -> Bool) {
    case unchanged {
      Some(filled) -> !changed(filled)
      None -> False
    }
  }
  list.flatten([
    [
      outbox.field_string("source", "fit"),
      outbox.field_string("external_id", summary.file_id),
      laps_field(summary.laps),
    ],
    case
      same(fn(filled) {
        filled.day != valid.day
        || filled.hour != valid.hour
        || filled.minute != valid.minute
      })
    {
      True -> [outbox.field_string("started_at", started_at(summary))]
      False -> []
    },
    case same(fn(filled) { filled.distance_m != valid.distance_m }) {
      True -> [outbox.field_float("distance_m", summary.distance_m)]
      False -> []
    },
    case same(fn(filled) { filled.duration_s != valid.duration_s }) {
      True -> [
        outbox.field_int("moving_time_s", summary.moving_time_s),
        outbox.field_int("elapsed_time_s", summary.elapsed_time_s),
      ]
      False -> []
    },
    case summary.max_hr {
      Some(bpm) -> [outbox.field_int("max_hr", bpm)]
      None -> []
    },
  ])
}

/// Laps in the shape the Strava hook stores them (ADR 0012), numbered from 1.
fn laps_field(laps: List(Lap)) -> #(String, String) {
  case laps {
    [] -> outbox.field_null("laps")
    _ -> #(
      "laps",
      json.array(list.index_map(laps, fn(lap, i) { #(lap, i + 1) }), fn(pair) {
        let #(lap, index) = pair
        json.object([
          #("index", json.int(index)),
          #("name", json.null()),
          #("distance_m", json.float(lap.distance_m)),
          #("moving_time_s", json.int(lap.moving_time_s)),
          #("elapsed_time_s", json.int(lap.elapsed_time_s)),
          #("elevation_gain_m", json.nullable(lap.elevation_gain_m, json.int)),
          #("avg_hr", json.nullable(lap.avg_hr, json.int)),
          #("max_hr", json.nullable(lap.max_hr, json.int)),
        ])
      })
        |> json.to_string,
    )
  }
}
