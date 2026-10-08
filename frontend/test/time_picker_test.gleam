import atlas/ui/time_picker.{
  Closed, Confirmed, Dismissed, HourPicked, Hours, KeyMoved, MinutePicked,
  Minutes, Open, Opened, PartChosen,
}
import gleam/option.{None, Some}
import gleam/string
import lustre/element

fn update(state, msg) {
  let #(next, _, picked) = time_picker.update("t", state, msg)
  #(next, picked)
}

pub fn opening_reads_the_field_or_starts_at_noon_test() {
  assert update(Closed, Opened("07:30")).0 == Open(7, 30, Hours)
  assert update(Closed, Opened("")).0 == Open(12, 0, Hours)
  assert update(Closed, Opened("25:00")).0 == Open(12, 0, Hours)
}

pub fn picking_the_hour_moves_on_to_the_minutes_test() {
  let #(state, _) = update(Open(7, 30, Hours), HourPicked(18))
  assert state == Open(18, 30, Minutes)
  let #(state, _) = update(state, MinutePicked(45))
  assert state == Open(18, 45, Minutes)
  let #(state, _) = update(state, PartChosen(Hours))
  assert state == Open(18, 45, Hours)
}

pub fn arrow_keys_change_the_part_on_show_by_one_and_wrap_test() {
  assert update(Open(23, 0, Hours), KeyMoved(1)).0 == Open(0, 0, Hours)
  assert update(Open(0, 0, Hours), KeyMoved(-1)).0 == Open(23, 0, Hours)
  assert update(Open(7, 59, Minutes), KeyMoved(1)).0 == Open(7, 0, Minutes)
  assert update(Open(7, 0, Minutes), KeyMoved(-1)).0 == Open(7, 59, Minutes)
}

pub fn ok_gives_the_time_with_two_digits_and_cancel_nothing_test() {
  assert update(Open(7, 5, Minutes), Confirmed) == #(Closed, Some("07:05"))
  assert update(Open(7, 5, Minutes), Dismissed) == #(Closed, None)
}

pub fn hours_sit_on_two_rings_test() {
  assert time_picker.hour_position(12) == #(0, False)
  assert time_picker.hour_position(3) == #(90, False)
  assert time_picker.hour_position(0) == #(0, True)
  assert time_picker.hour_position(15) == #(90, True)
}

pub fn the_dial_shows_the_part_on_show_test() {
  let hours =
    element.to_string(time_picker.view("t", Open(7, 30, Hours), fn(m) { m }))
  assert string.contains(hours, "aria-label=\"7 hours\"")
  assert string.contains(hours, "aria-label=\"00 hours\"")
  assert string.contains(hours, "aria-label=\"Hours 07\"")
  let minutes =
    element.to_string(time_picker.view("t", Open(7, 30, Minutes), fn(m) { m }))
  assert string.contains(minutes, "aria-label=\"30 minutes\"")
  assert !string.contains(minutes, "hours\"")
}
