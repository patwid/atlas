import atlas/date.{Date}
import atlas/ui/date_picker.{
  Closed, Confirmed, DayPicked, Dismissed, KeyMoved, MonthMoved, Open, Opened,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element

const id = "picker"

fn update(state, msg) {
  let #(next, _, picked) = date_picker.update(id, state, msg)
  #(next, picked)
}

pub fn a_month_is_laid_out_in_weeks_from_monday_test() {
  // October 2026 starts on a Thursday and has 31 days: five weeks.
  let weeks = date_picker.weeks(2026, 10)
  assert list.length(weeks) == 5
  let assert [first, ..] = weeks
  assert first
    == [
      None,
      None,
      None,
      Some(Date(2026, 10, 1)),
      Some(Date(2026, 10, 2)),
      Some(Date(2026, 10, 3)),
      Some(Date(2026, 10, 4)),
    ]
  let assert Ok(last) = list.last(weeks)
  assert list.last(last) == Ok(None)
  assert list.all(weeks, fn(week) { list.length(week) == 7 })
  // February 2027 starts on a Monday and fills exactly four weeks.
  assert list.length(date_picker.weeks(2027, 2)) == 4
}

pub fn opening_shows_the_fields_date_or_today_test() {
  let today = Date(2026, 10, 8)
  let #(state, picked) = update(Closed, Opened("2026-11-02", today))
  assert state == Open(2026, 11, Date(2026, 11, 2))
  assert picked == None
  let #(state, _) = update(Closed, Opened("", today))
  assert state == Open(2026, 10, today)
}

pub fn moving_the_month_keeps_the_chosen_day_test() {
  let start = Open(2026, 12, Date(2026, 12, 5))
  let #(next, _) = update(start, MonthMoved(1))
  assert next == Open(2027, 1, Date(2026, 12, 5))
  let #(back, _) = update(Open(2027, 1, Date(2026, 12, 5)), MonthMoved(-2))
  assert back == Open(2026, 11, Date(2026, 12, 5))
}

pub fn keys_move_the_chosen_day_across_months_test() {
  let start = Open(2026, 10, Date(2026, 10, 31))
  let #(next, _) = update(start, KeyMoved(date_picker.Days(1)))
  assert next == Open(2026, 11, Date(2026, 11, 1))
  let #(up, _) = update(start, KeyMoved(date_picker.Days(-7)))
  assert up == Open(2026, 10, Date(2026, 10, 24))
  // A month on from 31 January is the last day of February.
  let #(feb, _) =
    update(Open(2027, 1, Date(2027, 1, 31)), KeyMoved(date_picker.Months(1)))
  assert feb == Open(2027, 2, Date(2027, 2, 28))
  // Thursday 8 October: its week runs from Monday the 5th to Sunday the 11th.
  let thursday = Open(2026, 10, Date(2026, 10, 8))
  let #(home, _) = update(thursday, KeyMoved(date_picker.WeekStart))
  assert home == Open(2026, 10, Date(2026, 10, 5))
  let #(end, _) = update(thursday, KeyMoved(date_picker.WeekEnd))
  assert end == Open(2026, 10, Date(2026, 10, 11))
}

pub fn ok_gives_the_chosen_date_and_cancel_gives_nothing_test() {
  let #(state, _) =
    update(Open(2026, 10, Date(2026, 10, 8)), DayPicked(Date(2026, 10, 20)))
  let #(closed, picked) = update(state, Confirmed)
  assert closed == Closed
  assert picked == Some("2026-10-20")
  let #(closed, picked) = update(state, Dismissed)
  assert closed == Closed
  assert picked == None
}

pub fn the_grid_marks_the_chosen_day_and_today_with_one_tab_stop_test() {
  let html =
    element.to_string(
      date_picker.view(
        id,
        Open(2026, 10, Date(2026, 10, 20)),
        Date(2026, 10, 8),
        fn(msg) { msg },
      ),
    )
  assert string.contains(html, "October 2026")
  assert string.contains(html, "role=\"grid\"")
  assert string.contains(html, "aria-current=\"date\"")
  assert string.contains(html, "Tue, 20 Oct")
  assert list.length(string.split(html, "tabindex=\"0\"")) == 2
  assert list.length(string.split(html, "aria-selected=\"true\"")) == 2
  // Closed, the dialog is still there for opening, but empty.
  let closed =
    element.to_string(
      date_picker.view(id, Closed, Date(2026, 10, 8), fn(m) { m }),
    )
  assert !string.contains(closed, "role=\"grid\"")
  assert string.contains(closed, "id=\"picker\"")
}
