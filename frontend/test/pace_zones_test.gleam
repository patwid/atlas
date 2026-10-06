import atlas/pace_zones.{type Form, Form, PaceZones, Zone}
import gleam/option.{None, Some}

pub fn defaults_start_at_percentages_of_the_threshold_time_test() {
  assert pace_zones.defaults(300) == PaceZones(300, [420, 387, 342, 318, 297])
  assert pace_zones.to_form(pace_zones.defaults(300))
    == Form("5:00", ["7:00", "6:27", "5:42", "5:18", "4:57"])
  // Rounded down to whole seconds: 4:10 (250 s) gives 350, 322.5, 285, 265 and 247.5.
  assert pace_zones.defaults(250) == PaceZones(250, [350, 322, 285, 265, 247])
}

pub fn zones_end_a_second_slower_than_the_next_and_zone_5_is_open_test() {
  assert pace_zones.zones(pace_zones.defaults(300))
    == [
      Zone(1, 420, Some(388)),
      Zone(2, 387, Some(343)),
      Zone(3, 342, Some(319)),
      Zone(4, 318, Some(298)),
      Zone(5, 297, None),
    ]
}

pub fn zone_lookup_test() {
  let zones = pace_zones.defaults(300)
  assert pace_zones.zone_of(zones, 421) == Error(Nil)
  assert pace_zones.zone_of(zones, 420) == Ok(1)
  assert pace_zones.zone_of(zones, 388) == Ok(1)
  assert pace_zones.zone_of(zones, 387) == Ok(2)
  assert pace_zones.zone_of(zones, 300) == Ok(4)
  assert pace_zones.zone_of(zones, 297) == Ok(5)
  assert pace_zones.zone_of(zones, 180) == Ok(5)
}

fn form(threshold: String, starts: List(String)) -> Form {
  Form(threshold, starts)
}

pub fn paces_are_read_as_minutes_and_seconds_test() {
  assert pace_zones.parse(form(" 4:30 ", ["7", "6:00", "5:15", "4:45", "4:20"]))
    == Ok(PaceZones(270, [420, 360, 315, 285, 260]))
  assert pace_zones.parse(pace_zones.to_form(pace_zones.defaults(300)))
    == Ok(pace_zones.defaults(300))
}

pub fn paces_must_be_in_range_and_well_formed_test() {
  let starts = ["7:00", "6:27", "5:42", "5:18", "4:57"]
  let problem = fn(what) {
    "The " <> what <> " must be a pace from 2:00 to 15:00 per km, like 5:30."
  }
  assert pace_zones.parse(form("", starts)) == Error(problem("threshold pace"))
  assert pace_zones.parse(form("1:59", starts))
    == Error(problem("threshold pace"))
  assert pace_zones.parse(form("15:01", starts))
    == Error(problem("threshold pace"))
  assert pace_zones.parse(form("5:7", starts))
    == Error(problem("threshold pace"))
  assert pace_zones.parse(form("5:60", starts))
    == Error(problem("threshold pace"))
  assert pace_zones.parse(
      form("5:00", ["7:00", "6,27", "5:42", "5:18", "4:57"]),
    )
    == Error(problem("start of pace zone 2"))
}

pub fn zones_must_get_faster_test() {
  assert pace_zones.parse(
      form("5:00", ["7:00", "6:27", "6:27", "5:18", "4:57"]),
    )
    == Error("Pace zone 3 must start faster than pace zone 2.")
  assert pace_zones.parse(
      form("5:00", ["6:00", "6:27", "5:42", "5:18", "4:57"]),
    )
    == Error("Pace zone 2 must start faster than pace zone 1.")
  assert pace_zones.parse(form("5:00", ["7:00", "6:27", "5:42", "5:18"]))
    == Error("There must be five pace zones.")
}

pub fn zones_can_be_worked_out_again_from_the_threshold_test() {
  assert pace_zones.fill_from_threshold(form("4:00", ["1", "2", "3", "4", "5"]))
    == Ok(form("4:00", ["5:36", "5:09", "4:33", "4:14", "3:57"]))
  assert pace_zones.fill_from_threshold(form("x", []))
    == Error(
      "The threshold pace must be a pace from 2:00 to 15:00 per km, like 5:30.",
    )
}
