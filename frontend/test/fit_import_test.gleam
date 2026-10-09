import atlas/activity
import atlas/activity_form.{Form}
import atlas/fit.{Lap, Summary}
import atlas/fit_import
import atlas/outbox
import gleam/dict
import gleam/option.{None, Some}

/// 2025-09-28 13:20:12 UTC: 15:20 in Zurich.
fn summary() -> fit.Summary {
  Summary(
    file_id: "3456789012-1128000000",
    started_at: 1_759_065_612,
    sport: activity.TrailRun,
    distance_m: 10_234.56,
    moving_time_s: 2901,
    elapsed_time_s: 3000,
    elevation_gain_m: Some(412),
    avg_hr: Some(155),
    max_hr: Some(171),
    laps: [
      Lap(5000.0, 1450, 1500, Some(200), Some(150), None),
      Lap(5234.56, 1451, 1500, None, None, None),
    ],
  )
}

fn imported() -> fit_import.Import {
  fit_import.new(summary(), "morning.fit", 120)
}

fn saved(form: activity_form.Form) -> outbox.Fields {
  let assert Ok(valid) = activity_form.validate(form)
  fit_import.create_fields("u1", imported(), valid, 120)
}

fn field(fields: outbox.Fields, name: String) -> Result(String, Nil) {
  dict.get(fields, name)
}

pub fn the_file_fills_in_the_form_in_local_time_test() {
  assert imported().filled
    == Form(
      date: "2025-09-28",
      time: "15:20",
      sport: activity.TrailRun,
      name: "",
      distance_km: "10.235",
      duration: "0:48:21",
      elevation_m: "412",
      avg_hr: "155",
      error: None,
    )
}

pub fn missing_values_leave_their_fields_empty_test() {
  let bare =
    Summary(..summary(), elevation_gain_m: None, avg_hr: None, distance_m: 0.0)
  let form = fit_import.new(bare, "x.fit", 0).filled
  assert form.elevation_m == ""
  assert form.avg_hr == ""
  assert form.distance_km == ""
}

pub fn what_the_user_left_alone_is_written_as_the_file_says_test() {
  let fields = saved(imported().filled)
  assert field(fields, "owner") == Ok("\"u1\"")
  assert field(fields, "source") == Ok("\"fit\"")
  assert field(fields, "external_id") == Ok("\"3456789012-1128000000\"")
  assert field(fields, "started_at") == Ok("\"2025-09-28 13:20:12.000Z\"")
  assert field(fields, "sport") == Ok("\"trail_run\"")
  assert field(fields, "distance_m") == Ok("10234.56")
  assert field(fields, "moving_time_s") == Ok("2901")
  assert field(fields, "elapsed_time_s") == Ok("3000")
  assert field(fields, "elevation_gain_m") == Ok("412")
  assert field(fields, "avg_hr") == Ok("155")
  assert field(fields, "max_hr") == Ok("171")
}

pub fn laps_are_stored_like_stravas_test() {
  assert field(saved(imported().filled), "laps")
    == Ok(
      "[{\"index\":1,\"name\":null,\"distance_m\":5000,\"moving_time_s\":1450,\"elapsed_time_s\":1500,\"elevation_gain_m\":200,\"avg_hr\":150,\"max_hr\":null},"
      <> "{\"index\":2,\"name\":null,\"distance_m\":5234.56,\"moving_time_s\":1451,\"elapsed_time_s\":1500,\"elevation_gain_m\":null,\"avg_hr\":null,\"max_hr\":null}]",
    )
}

pub fn a_file_without_laps_stores_none_test() {
  let fields =
    fit_import.create_fields(
      "u1",
      fit_import.new(Summary(..summary(), laps: []), "x.fit", 120),
      {
        let assert Ok(valid) = activity_form.validate(imported().filled)
        valid
      },
      120,
    )
  assert field(fields, "laps") == Ok("null")
}

pub fn what_the_user_changed_is_written_as_typed_test() {
  let fields =
    saved(
      Form(
        ..imported().filled,
        time: "15:30",
        distance_km: "10.5",
        duration: "50",
      ),
    )
  assert field(fields, "started_at") == Ok("\"2025-09-28 13:30:00.000Z\"")
  assert field(fields, "distance_m") == Ok("10500")
  assert field(fields, "moving_time_s") == Ok("3000")
  assert field(fields, "elapsed_time_s") == Ok("3000")
  // Still from the file.
  assert field(fields, "source") == Ok("\"fit\"")
  assert field(fields, "max_hr") == Ok("171")
}

pub fn a_deleted_import_is_brought_back_test() {
  let assert Ok(valid) = activity_form.validate(imported().filled)
  let fields = fit_import.revive_fields(imported(), valid, 120)
  assert field(fields, "deleted") == Ok("false")
  assert field(fields, "owner") == Error(Nil)
  assert field(fields, "source") == Error(Nil)
  assert field(fields, "external_id") == Ok("\"3456789012-1128000000\"")
  assert field(fields, "distance_m") == Ok("10234.56")
}

fn row(owner: String, source: activity.Source, external_id: String) {
  activity_form.Row(
    activity: activity.Activity(
      "a1",
      source,
      "2025-09-28 13:20:12.000Z",
      activity.Run,
      0.0,
      0,
    ),
    owner_id: owner,
    name: "",
    elevation_m: 0.0,
    avg_hr: 0,
    updated: "x",
    external_id: external_id,
  )
}

pub fn the_same_file_is_found_among_the_users_own_imports_test() {
  let same = row("u1", activity.Fit, "3456789012-1128000000")
  assert fit_import.already_imported([same], "u1", summary()) == Some(same)
  assert fit_import.already_imported(
      [
        row("u2", activity.Fit, "3456789012-1128000000"),
        row("u1", activity.Strava, "3456789012-1128000000"),
        row("u1", activity.Fit, "other"),
      ],
      "u1",
      summary(),
    )
    == None
}
