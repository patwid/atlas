import atlas/lactate_zones.{LactateZones, Zone}
import gleam/option.{None, Some}

pub fn defaults_test() {
  assert lactate_zones.to_form(lactate_zones.defaults())
    == ["1.0", "1.5", "2.5", "4.0", "6.0"]
}

pub fn zones_end_a_tenth_below_the_next_and_zone_5_is_open_test() {
  assert lactate_zones.zones(lactate_zones.defaults())
    == [
      Zone(1, 10, Some(14)),
      Zone(2, 15, Some(24)),
      Zone(3, 25, Some(39)),
      Zone(4, 40, Some(59)),
      Zone(5, 60, None),
    ]
}

pub fn zone_lookup_test() {
  let zones = lactate_zones.defaults()
  assert lactate_zones.zone_of(zones, 9) == Error(Nil)
  assert lactate_zones.zone_of(zones, 10) == Ok(1)
  assert lactate_zones.zone_of(zones, 24) == Ok(2)
  assert lactate_zones.zone_of(zones, 39) == Ok(3)
  assert lactate_zones.zone_of(zones, 40) == Ok(4)
  assert lactate_zones.zone_of(zones, 150) == Ok(5)
}

pub fn values_are_read_with_a_point_or_a_comma_test() {
  assert lactate_zones.parse(["0,8", "1.5", " 2.5 ", "4", "6"])
    == Ok(LactateZones([8, 15, 25, 40, 60]))
  assert lactate_zones.parse(lactate_zones.to_form(lactate_zones.defaults()))
    == Ok(lactate_zones.defaults())
}

pub fn values_must_be_in_range_with_one_decimal_test() {
  let problem = fn(n) {
    "The start of lactate zone "
    <> n
    <> " must be a number from 0.1 to 30.0 with at most one decimal."
  }
  assert lactate_zones.parse(["0", "1.5", "2.5", "4.0", "6.0"])
    == Error(problem("1"))
  assert lactate_zones.parse(["1.0", "1.55", "2.5", "4.0", "6.0"])
    == Error(problem("2"))
  assert lactate_zones.parse(["1.0", "1.5", "2.5", "4.0", "30.1"])
    == Error(problem("5"))
  assert lactate_zones.parse(["1.0", "", "2.5", "4.0", "6.0"])
    == Error(problem("2"))
}

pub fn zones_must_rise_test() {
  assert lactate_zones.parse(["1.0", "1.5", "1.5", "4.0", "6.0"])
    == Error("Lactate zone 3 must start higher than lactate zone 2.")
  assert lactate_zones.parse(["1.0", "1.5", "2.5", "4.0"])
    == Error("There must be five lactate zones.")
}

pub fn stored_values_round_to_tenths_test() {
  assert lactate_zones.tenths_of(2.5) == 25
  assert lactate_zones.tenths_of(0.30000000000000004) == 3
  assert lactate_zones.format(3) == "0.3"
  assert lactate_zones.format(300) == "30.0"
}
