import atlas/hr_zones.{Form, HrZones}
import atlas/hr_zones_page.{
  Create, Edit, FillFromMaxClicked, MaxChanged, ResetClicked, RowsRead,
  StartChanged, Submitted,
}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import lustre/element

fn update(model: hr_zones_page.Model, msg: hr_zones_page.Msg) {
  let #(next, _, actions) = hr_zones_page.update(model, msg, "me")
  #(next, actions)
}

fn rows(text: String) {
  let assert Ok(value) = json.parse(text, decode.list(decode.dynamic))
  RowsRead(Ok(value))
}

const saved =
  "[{\"id\":\"me\",\"owner\":\"me\",\"max_hr\":185,\"hr_zone1_min\":110,\"hr_zone2_min\":140,\"hr_zone3_min\":152,\"hr_zone4_min\":165,\"hr_zone5_min\":176,\"deleted\":false,\"updated\":\"T1\"}]"

pub fn the_form_starts_with_the_defaults_test() {
  let #(model, _) = update(hr_zones_page.new(), rows("[]"))
  assert model.form == hr_zones.to_form(hr_zones.defaults(190))
  assert hr_zones_page.current(model, "me") == hr_zones.defaults(190)
  let html = element.to_string(hr_zones_page.view(model, "me"))
  assert string.contains(html, "These are the default zones")
  assert string.contains(html, "to 113 bpm")
}

pub fn saving_the_defaults_creates_the_row_under_the_users_id_test() {
  let #(model, _) = update(hr_zones_page.new(), rows("[]"))
  let #(model, actions) = update(model, Submitted)
  assert actions
    == [Create("me", hr_zones.fields("me", hr_zones.defaults(190)))]
  assert model.saved
}

pub fn saved_zones_fill_the_form_and_an_edit_uses_their_base_test() {
  let #(model, _) = update(hr_zones_page.new(), rows(saved))
  let own = HrZones(185, [110, 140, 152, 165, 176])
  assert model.form == hr_zones.to_form(own)
  let #(model, _) = update(model, StartChanged(2, "142"))
  let #(_, actions) = update(model, Submitted)
  assert actions
    == [
      Edit(
        "me",
        hr_zones.fields("me", HrZones(185, [110, 142, 152, 165, 176])),
        "T1",
      ),
    ]
}

pub fn a_coachs_device_ignores_the_athletes_zones_test() {
  let athletes = string.replace(saved, "\"me\"", "\"athlete\"")
  let #(model, _) = update(hr_zones_page.new(), rows(athletes))
  assert model.form == hr_zones.to_form(hr_zones.defaults(190))
  let #(_, actions) = update(model, Submitted)
  let assert [Create("me", _)] = actions
}

pub fn an_invalid_form_is_not_saved_test() {
  let #(model, _) = update(hr_zones_page.new(), rows("[]"))
  let #(model, _) = update(model, StartChanged(3, "100"))
  let #(model, actions) = update(model, Submitted)
  assert actions == []
  assert model.form.error == Some("Zone 3 must start higher than zone 2.")
  assert string.contains(
    element.to_string(hr_zones_page.view(model, "me")),
    "Zone 3 must start higher than zone 2.",
  )
}

pub fn synced_changes_do_not_overwrite_what_the_user_is_typing_test() {
  let #(model, _) = update(hr_zones_page.new(), rows("[]"))
  let #(model, _) = update(model, MaxChanged("200"))
  let #(model, _) = update(model, rows(saved))
  assert model.form.max_hr == "200"
  // Undoing goes back to the newest saved zones.
  let #(model, _) = update(model, ResetClicked)
  assert model.form == hr_zones.to_form(HrZones(185, [110, 140, 152, 165, 176]))
  assert !model.edited
}

pub fn zones_are_worked_out_from_a_new_maximum_test() {
  let #(model, _) = update(hr_zones_page.new(), rows("[]"))
  let #(model, _) = update(model, MaxChanged("200"))
  let #(model, _) = update(model, FillFromMaxClicked)
  assert model.form == Form("200", ["100", "120", "140", "160", "180"], None)
  assert model.edited
}

pub fn an_unusable_stored_row_falls_back_to_the_defaults_test() {
  let broken =
    string.replace(saved, "\"hr_zone2_min\":140", "\"hr_zone2_min\":100")
  let #(model, _) = update(hr_zones_page.new(), rows(broken))
  assert model.rows == []
  assert hr_zones_page.current(model, "me") == hr_zones.defaults(190)
}
