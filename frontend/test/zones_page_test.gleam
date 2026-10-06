import atlas/athlete_settings
import atlas/hr_zones.{HrZones}
import atlas/lactate_zones.{LactateZones}
import atlas/zones_page.{
  Create, Edit, FillFromMaxClicked, HrStartChanged, LactateStartChanged,
  MaxChanged, ResetClicked, RowsRead, Submitted,
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

const saved =
  "[{\"id\":\"me\",\"owner\":\"me\",\"max_hr\":185,\"hr_zone1_min\":110,\"hr_zone2_min\":140,\"hr_zone3_min\":152,\"hr_zone4_min\":165,\"hr_zone5_min\":176,\"lactate_zone1_min\":0.8,\"lactate_zone2_min\":1.5,\"lactate_zone3_min\":2.5,\"lactate_zone4_min\":4,\"lactate_zone5_min\":6,\"deleted\":false,\"updated\":\"T1\"}]"

const own_hr = HrZones(185, [110, 140, 152, 165, 176])

const own_lactate = LactateZones([8, 15, 25, 40, 60])

fn loaded(text: String) -> zones_page.Model {
  let #(model, _) = update(zones_page.new(), rows(text))
  model
}

pub fn the_form_starts_with_the_defaults_test() {
  let model = loaded("[]")
  assert model.hr == hr_zones.to_form(hr_zones.defaults(190))
  assert model.lactate == ["1.0", "1.5", "2.5", "4.0", "6.0"]
  let html = element.to_string(zones_page.view(model, "me"))
  assert string.contains(html, "These are the default zones")
  assert string.contains(html, "to 113 bpm")
  assert string.contains(html, "to 1.4 mmol/L")
  assert string.contains(html, "mmol/L and above")
}

pub fn saving_the_defaults_creates_the_row_under_the_users_id_test() {
  let #(model, actions) = update(loaded("[]"), Submitted)
  assert actions
    == [
      Create(
        "me",
        athlete_settings.fields(
          "me",
          hr_zones.defaults(190),
          lactate_zones.defaults(),
        ),
      ),
    ]
  assert model.saved
}

pub fn saved_zones_fill_the_form_and_an_edit_uses_their_base_test() {
  let model = loaded(saved)
  assert model.hr == hr_zones.to_form(own_hr)
  assert model.lactate == lactate_zones.to_form(own_lactate)
  let #(model, _) = update(model, HrStartChanged(2, "142"))
  let #(model, _) = update(model, LactateStartChanged(3, "2,8"))
  let #(_, actions) = update(model, Submitted)
  assert actions
    == [
      Edit(
        "me",
        athlete_settings.fields(
          "me",
          HrZones(185, [110, 142, 152, 165, 176]),
          LactateZones([8, 15, 28, 40, 60]),
        ),
        "T1",
      ),
    ]
}

pub fn a_row_saved_before_lactate_zones_keeps_its_heart_rate_zones_test() {
  let old =
    "[{\"id\":\"me\",\"owner\":\"me\",\"max_hr\":185,\"hr_zone1_min\":110,\"hr_zone2_min\":140,\"hr_zone3_min\":152,\"hr_zone4_min\":165,\"hr_zone5_min\":176,\"lactate_zone1_min\":0,\"updated\":\"T0\"}]"
  let model = loaded(old)
  assert zones_page.current(model, "me") == #(own_hr, lactate_zones.defaults())
}

pub fn a_coachs_device_ignores_the_athletes_zones_test() {
  let model = loaded(string.replace(saved, "\"me\"", "\"athlete\""))
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
  assert string.contains(
    element.to_string(zones_page.view(model, "me")),
    "Lactate zone 3 must start higher than lactate zone 2.",
  )
  let #(model, _) = update(model, HrStartChanged(3, "100"))
  let #(model, _) = update(model, Submitted)
  assert model.error == Some("Zone 3 must start higher than zone 2.")
}

pub fn synced_changes_do_not_overwrite_what_the_user_is_typing_test() {
  let #(model, _) = update(loaded("[]"), MaxChanged("200"))
  let #(model, _) = update(model, rows(saved))
  assert model.hr.max_hr == "200"
  // Undoing goes back to the newest saved zones.
  let #(model, _) = update(model, ResetClicked)
  assert zones_page.current(model, "me") == #(own_hr, own_lactate)
  assert model.hr == hr_zones.to_form(own_hr)
  assert !model.edited
}

pub fn zones_are_worked_out_from_a_new_maximum_test() {
  let #(model, _) = update(loaded("[]"), MaxChanged("200"))
  let #(model, _) = update(model, FillFromMaxClicked)
  assert model.hr == hr_zones.Form("200", ["100", "120", "140", "160", "180"])
  assert model.edited
  let #(model, _) = update(model, MaxChanged("x"))
  let #(model, _) = update(model, FillFromMaxClicked)
  assert model.error
    == Some("The maximum heart rate must be a whole number from 30 to 250.")
}

pub fn an_unusable_stored_row_falls_back_to_the_defaults_test() {
  let broken =
    string.replace(saved, "\"hr_zone2_min\":140", "\"hr_zone2_min\":100")
  let model = loaded(broken)
  assert model.rows == []
  assert zones_page.current(model, "me")
    == #(hr_zones.defaults(190), lactate_zones.defaults())
}
