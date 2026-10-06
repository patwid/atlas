import atlas/hr_zones.{Form, HrZones, Zone}

pub fn defaults_start_at_50_to_90_percent_of_the_maximum_test() {
  assert hr_zones.defaults(190) == HrZones(190, [95, 114, 133, 152, 171])
}

pub fn zones_do_not_overlap_and_zone_5_ends_at_the_maximum_test() {
  assert hr_zones.zones(hr_zones.defaults(190))
    == [
      Zone(1, 95, 113),
      Zone(2, 114, 132),
      Zone(3, 133, 151),
      Zone(4, 152, 170),
      Zone(5, 171, 190),
    ]
}

pub fn own_zones_need_not_follow_the_percentages_test() {
  let own = HrZones(185, [110, 140, 152, 165, 176])
  assert hr_zones.zones(own)
    == [
      Zone(1, 110, 139),
      Zone(2, 140, 151),
      Zone(3, 152, 164),
      Zone(4, 165, 175),
      Zone(5, 176, 185),
    ]
  assert hr_zones.zone_of(own, 139) == Ok(1)
  assert hr_zones.zone_of(own, 140) == Ok(2)
}

pub fn zone_lookup_test() {
  let zones = hr_zones.defaults(190)
  assert hr_zones.zone_of(zones, 150) == Ok(3)
  assert hr_zones.zone_of(zones, 95) == Ok(1)
  assert hr_zones.zone_of(zones, 94) == Error(Nil)
  assert hr_zones.zone_of(zones, 113) == Ok(1)
  assert hr_zones.zone_of(zones, 114) == Ok(2)
  assert hr_zones.zone_of(zones, 190) == Ok(5)
  assert hr_zones.zone_of(zones, 200) == Ok(5)
}

fn form(max: String, starts: List(String)) -> hr_zones.Form {
  Form(max, starts)
}

pub fn a_valid_form_is_read_test() {
  assert hr_zones.parse(form(" 185 ", ["110", "140", "152", "165", "176"]))
    == Ok(HrZones(185, [110, 140, 152, 165, 176]))
  // Zone 5 may start at the maximum itself.
  assert hr_zones.parse(form("185", ["110", "140", "152", "165", "185"]))
    == Ok(HrZones(185, [110, 140, 152, 165, 185]))
}

pub fn the_form_round_trips_test() {
  let zones = HrZones(185, [110, 140, 152, 165, 176])
  assert hr_zones.parse(hr_zones.to_form(zones)) == Ok(zones)
}

pub fn values_must_be_whole_numbers_in_range_test() {
  let starts = ["95", "114", "133", "152", "171"]
  assert hr_zones.parse(form("", starts))
    == Error("The maximum heart rate must be a whole number from 30 to 250.")
  assert hr_zones.parse(form("251", starts))
    == Error("The maximum heart rate must be a whole number from 30 to 250.")
  assert hr_zones.parse(form("190", ["95", "114", "13x", "152", "171"]))
    == Error("The start of zone 3 must be a whole number from 30 to 250.")
  assert hr_zones.parse(form("190", ["29", "114", "133", "152", "171"]))
    == Error("The start of zone 1 must be a whole number from 30 to 250.")
}

pub fn zones_must_rise_and_stay_below_the_maximum_test() {
  assert hr_zones.parse(form("190", ["95", "114", "114", "152", "171"]))
    == Error("Zone 3 must start higher than zone 2.")
  assert hr_zones.parse(form("190", ["120", "114", "133", "152", "171"]))
    == Error("Zone 2 must start higher than zone 1.")
  assert hr_zones.parse(form("170", ["95", "114", "133", "152", "171"]))
    == Error("Zone 5 must start at or below the maximum heart rate.")
  assert hr_zones.parse(form("190", ["95", "114", "133", "152"]))
    == Error("There must be five zones.")
}

pub fn zones_can_be_worked_out_again_from_the_maximum_test() {
  let typed = form("200", ["1", "2", "3", "4", "5"])
  assert hr_zones.fill_from_max(typed)
    == Ok(form("200", ["100", "120", "140", "160", "180"]))
  assert hr_zones.fill_from_max(form("abc", ["1", "2", "3", "4", "5"]))
    == Error("The maximum heart rate must be a whole number from 30 to 250.")
}
