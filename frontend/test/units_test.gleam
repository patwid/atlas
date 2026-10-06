import atlas/units

pub fn pace_test() {
  assert units.pace_seconds_per_km(10_000.0, 3000) == Ok(300)
  assert units.pace_seconds_per_km(5000.0, 1650) == Ok(330)
  assert units.pace_seconds_per_km(1609.34, 480) == Ok(298)
  assert units.pace_seconds_per_km(0.0, 3000) == Error(Nil)
  assert units.pace_seconds_per_km(10_000.0, 0) == Error(Nil)
  assert units.pace_seconds_per_km(-5.0, 100) == Error(Nil)
}

pub fn format_pace_test() {
  assert units.format_pace(330) == "5:30 /km"
  assert units.format_pace(305) == "5:05 /km"
}

pub fn format_duration_test() {
  assert units.format_duration(0) == "0:00"
  assert units.format_duration(59) == "0:59"
  assert units.format_duration(2710) == "45:10"
  assert units.format_duration(3600) == "1:00:00"
  assert units.format_duration(3723) == "1:02:03"
  assert units.format_duration(-5) == "0:00"
}

pub fn format_distance_test() {
  assert units.format_distance_km(10_234.5) == "10.23 km"
  assert units.format_distance_km(10_235.0) == "10.24 km"
  assert units.format_distance_km(5000.0) == "5.00 km"
  assert units.format_distance_km(42_195.0) == "42.20 km"
  assert units.format_distance_km(0.0) == "0.00 km"
  assert units.format_distance_km(900.0) == "0.90 km"
  assert units.format_distance_km(-10.0) == "0.00 km"
}
