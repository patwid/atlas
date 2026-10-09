import atlas/athlete_settings.{Zones}
import atlas/hr_zones.{HrZones}
import atlas/lactate_zones.{LactateZones}
import atlas/pace_zones.{PaceZones}
import atlas/zones_page.{
  Create, Edit, FillFromMaxClicked, FillFromThresholdClicked, HrStartChanged,
  LactateStartChanged, MaxChanged, PaceStartChanged, ResetClicked, RowsRead,
  Submitted, ThresholdChanged,
}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{Some}
import gleam/string
import lustre/element

fn update(model: zones_page.Model, msg: zones_page.Msg) {
  let #(next, _, actions) = zones_page.update(model, msg, "me")
  #(next, actions)
}

fn rows(text: String) {
  let assert Ok(value) = json.parse(text, decode.list(decode.dynamic))
  RowsRead(Ok(value))
}

const hr_json =
  "\"owner\":\"me\",\"max_hr\":185,\"hr_zone1_min\":110,\"hr_zone2_min\":140,\"hr_zone3_min\":152,\"hr_zone4_min\":165,\"hr_zone5_min\":176"

const lactate_json =
  "\"lactate_zone1_min\":0.8,\"lactate_zone2_min\":1.5,\"lactate_zone3_min\":2.5,\"lactate_zone4_min\":4,\"lactate_zone5_min\":6"

const pace_json =
  "\"threshold_pace_s\":270,\"pace_zone1_start_s\":420,\"pace_zone2_start_s\":360,\"pace_zone3_start_s\":315,\"pace_zone4_start_s\":285,\"pace_zone5_start_s\":260"

fn row(parts: List(String)) -> String {
  "[{\"id\":\"me\","
  <> string.join(parts, ",")
  <> ",\"deleted\":false,\"updated\":\"T1\"}]"
}

const own_hr = HrZones(185, [110, 140, 152, 165, 176])

const own_lactate = LactateZones([8, 15, 25, 40, 60])

const own_pace = PaceZones(270, [420, 360, 315, 285, 260])

fn saved() -> String {
  row([hr_json, lactate_json, pace_json])
}

fn loaded(text: String) -> zones_page.Model {
  let #(model, _) = update(zones_page.new(), rows(text))
  model
}

pub fn the_form_starts_with_the_defaults_test() {
  let model = loaded("[]")
  assert model.hr == hr_zones.to_form(hr_zones.defaults(190))
  assert model.lactate == ["1.0", "1.5", "2.5", "4.0", "6.0"]
  assert model.pace
    == pace_zones.Form("5:00", ["7:00", "6:27", "5:42", "5:18", "4:57"])
  let html = element.to_string(zones_page.view(model, "me"))
  assert string.contains(html, "These are the default zones")
  assert string.contains(html, "to 113 bpm")
  assert string.contains(html, "to 1.4 mmol/L")
  assert string.contains(html, "mmol/L and above")
  assert string.contains(html, "to 6:28 /km")
  assert string.contains(html, "/km and faster")
}

pub fn saving_the_defaults_creates_the_row_under_the_users_id_test() {
  let #(model, actions) = update(loaded("[]"), Submitted)
  assert actions
    == [
      Create("me", athlete_settings.fields("me", athlete_settings.defaults())),
    ]
  assert model.saved
}

pub fn saved_zones_fill_the_form_and_an_edit_uses_their_base_test() {
  let model = loaded(saved())
  assert model.hr == hr_zones.to_form(own_hr)
  assert model.lactate == lactate_zones.to_form(own_lactate)
  assert model.pace == pace_zones.to_form(own_pace)
  let #(model, _) = update(model, HrStartChanged(2, "142"))
  let #(model, _) = update(model, LactateStartChanged(3, "2,8"))
  let #(model, _) = update(model, PaceStartChanged(4, "4:40"))
  let #(_, actions) = update(model, Submitted)
  assert actions
    == [
      Edit(
        "me",
        athlete_settings.fields(
          "me",
          Zones(
            HrZones(185, [110, 142, 152, 165, 176]),
            LactateZones([8, 15, 28, 40, 60]),
            PaceZones(270, [420, 360, 315, 280, 260]),
          ),
        ),
        "T1",
      ),
    ]
}

pub fn a_row_saved_before_lactate_and_pace_zones_keeps_its_heart_rate_zones_test() {
  let model = loaded(row([hr_json, "\"lactate_zone1_min\":0"]))
  assert zones_page.current(model, "me")
    == Zones(own_hr, lactate_zones.defaults(), pace_zones.defaults(300))
  // Lactate zones from before pace zones existed are kept too.
  let model = loaded(row([hr_json, lactate_json, "\"threshold_pace_s\":0"]))
  assert zones_page.current(model, "me")
    == Zones(own_hr, own_lactate, pace_zones.defaults(300))
}

pub fn a_coachs_device_ignores_the_athletes_zones_test() {
  let model = loaded(string.replace(saved(), "\"me\"", "\"athlete\""))
  assert model.hr == hr_zones.to_form(hr_zones.defaults(190))
  let #(_, actions) = update(model, Submitted)
  let assert [Create("me", _)] = actions
}

pub fn an_invalid_form_is_not_saved_test() {
  let #(model, _) = update(loaded("[]"), LactateStartChanged(3, "1.2"))
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.error
    == Some("Lactate zone 3 must start higher than lactate zone 2.")
  assert model.error_field == "lactate-zone-3"
  // Under the input it is about, which is marked.
  let html = element.to_string(zones_page.view(model, "me"))
  assert string.contains(
    html,
    "lactate-zone-3-help\" role=\"alert\">Lactate zone 3 must start higher than lactate zone 2.",
  )
  assert string.contains(
    html,
    "aria-describedby=\"lactate-zone-3-help\" aria-invalid=\"true\"",
  )
  // The problem higher up the form is shown first.
  let #(model, _) = update(model, PaceStartChanged(3, "7:30"))
  let #(model, _) = update(model, Submitted)
  assert model.error == Some("Pace zone 3 must start faster than pace zone 2.")
  assert model.error_field == "pace-zone-3"
  let #(model, _) = update(model, HrStartChanged(3, "100"))
  let #(model, _) = update(model, Submitted)
  assert model.error == Some("Zone 3 must start higher than zone 2.")
  assert model.error_field == "hr-zone-3"
  let #(model, _) = update(model, MaxChanged("x"))
  let #(model, _) = update(model, Submitted)
  assert model.error_field == "hr-max"
}

pub fn synced_changes_do_not_overwrite_what_the_user_is_typing_test() {
  let #(model, _) = update(loaded("[]"), ThresholdChanged("4:30"))
  let #(model, _) = update(model, rows(saved()))
  assert model.pace.threshold == "4:30"
  // Undoing goes back to the newest saved zones.
  let #(model, _) = update(model, ResetClicked)
  assert zones_page.current(model, "me") == Zones(own_hr, own_lactate, own_pace)
  assert model.pace == pace_zones.to_form(own_pace)
  assert !model.edited
}

pub fn zones_are_worked_out_from_a_new_maximum_or_threshold_test() {
  let #(model, _) = update(loaded("[]"), MaxChanged("200"))
  let #(model, _) = update(model, FillFromMaxClicked)
  assert model.hr == hr_zones.Form("200", ["100", "120", "140", "160", "180"])
  assert model.edited
  let #(model, _) = update(model, ThresholdChanged("4:00"))
  let #(model, _) = update(model, FillFromThresholdClicked)
  assert model.pace
    == pace_zones.Form("4:00", ["5:36", "5:09", "4:33", "4:14", "3:57"])
  let #(model, _) = update(model, ThresholdChanged("x"))
  let #(model, _) = update(model, FillFromThresholdClicked)
  assert model.error
    == Some(
      "The threshold pace must be a pace from 2:00 to 15:00 per km, like 5:30.",
    )
}

pub fn an_unusable_stored_row_falls_back_to_the_defaults_test() {
  let broken =
    string.replace(saved(), "\"hr_zone2_min\":140", "\"hr_zone2_min\":100")
  let model = loaded(broken)
  assert model.rows == []
  assert zones_page.current(model, "me") == athlete_settings.defaults()
}

pub fn the_form_waits_for_the_saved_zones_test() {
  let html = element.to_string(zones_page.view(zones_page.new(), "me"))
  assert string.contains(html, "Loading…")
  assert !string.contains(html, "hr-max")
}
