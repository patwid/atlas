import atlas/athlete_settings.{Row, Zones}
import atlas/hr_zones.{HrZones}
import atlas/lactate_zones.{LactateZones}
import atlas/outbox
import atlas/pace_zones.{PaceZones}
import gleam/dict
import gleam/option.{None, Some}

pub fn every_value_is_written_test() {
  assert athlete_settings.fields(
      "u1",
      Zones(
        HrZones(185, [110, 140, 152, 165, 176]),
        LactateZones([8, 15, 25, 40, 60]),
        PaceZones(270, [420, 360, 315, 285, 260]),
      ),
    )
    == dict.from_list([
      outbox.field_string("owner", "u1"),
      outbox.field_int("max_hr", 185),
      outbox.field_int("hr_zone1_min", 110),
      outbox.field_int("hr_zone2_min", 140),
      outbox.field_int("hr_zone3_min", 152),
      outbox.field_int("hr_zone4_min", 165),
      outbox.field_int("hr_zone5_min", 176),
      outbox.field_float("lactate_zone1_min", 0.8),
      outbox.field_float("lactate_zone2_min", 1.5),
      outbox.field_float("lactate_zone3_min", 2.5),
      outbox.field_float("lactate_zone4_min", 4.0),
      outbox.field_float("lactate_zone5_min", 6.0),
      outbox.field_int("threshold_pace_s", 270),
      outbox.field_int("pace_zone1_start_s", 420),
      outbox.field_int("pace_zone2_start_s", 360),
      outbox.field_int("pace_zone3_start_s", 315),
      outbox.field_int("pace_zone4_start_s", 285),
      outbox.field_int("pace_zone5_start_s", 260),
    ])
}

pub fn the_row_is_found_by_owner_and_defaults_apply_without_one_test() {
  let mine =
    Row(
      "me",
      hr_zones.defaults(180),
      LactateZones([8, 15, 25, 40, 60]),
      pace_zones.defaults(270),
      "t1",
    )
  let athletes =
    Row(
      "athlete",
      hr_zones.defaults(200),
      lactate_zones.defaults(),
      pace_zones.defaults(300),
      "t2",
    )
  assert athlete_settings.row_of([athletes, mine], "me") == Some(mine)
  assert athlete_settings.row_of([athletes], "me") == None
  assert athlete_settings.current([athletes, mine], "me")
    == Zones(mine.hr, mine.lactate, mine.pace)
  assert athlete_settings.current([athletes], "me")
    == Zones(
      hr_zones.defaults(190),
      lactate_zones.defaults(),
      pace_zones.defaults(300),
    )
  assert athlete_settings.defaults() == athlete_settings.current([], "me")
}
