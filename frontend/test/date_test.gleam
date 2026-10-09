import atlas/date.{Date, Friday, Monday, Saturday, Sunday, Thursday}
import gleam/order

pub fn parse_and_print_test() {
  assert date.parse("2026-10-06") == Ok(Date(2026, 10, 6))
  assert date.to_string(Date(2026, 1, 5)) == "2026-01-05"
  assert date.to_string(Date(987, 1, 5)) == "0987-01-05"
}

pub fn parse_rejects_bad_input_test() {
  assert date.parse("2026-13-01") == Error(Nil)
  assert date.parse("2026-02-30") == Error(Nil)
  assert date.parse("2026-2-3") == Error(Nil)
  assert date.parse("06.10.2026") == Error(Nil)
  assert date.parse("") == Error(Nil)
  assert date.parse("2026-10-06T00:00") == Error(Nil)
}

pub fn leap_years_test() {
  assert date.parse("2024-02-29") == Ok(Date(2024, 2, 29))
  assert date.parse("2026-02-29") == Error(Nil)
  assert date.parse("1900-02-29") == Error(Nil)
  assert date.parse("2000-02-29") == Ok(Date(2000, 2, 29))
}

pub fn epoch_days_test() {
  assert date.to_epoch_days(Date(1970, 1, 1)) == 0
  assert date.to_epoch_days(Date(1970, 1, 2)) == 1
  assert date.to_epoch_days(Date(1969, 12, 31)) == -1
  assert date.to_epoch_days(Date(2000, 3, 1)) == 11_017
  assert date.to_epoch_days(Date(2026, 10, 6)) == 20_732
}

pub fn epoch_days_round_trip_test() {
  assert date.from_epoch_days(0) == Date(1970, 1, 1)
  assert date.from_epoch_days(-1) == Date(1969, 12, 31)
  assert date.from_epoch_days(11_017) == Date(2000, 3, 1)
  assert date.from_epoch_days(date.to_epoch_days(Date(2024, 2, 29)))
    == Date(2024, 2, 29)
  // Every day over several years survives the round trip, including 1900 and 2100 (not leap years).
  assert round_trips(-25_000, 25_000)
}

fn round_trips(from: Int, to: Int) -> Bool {
  case from > to {
    True -> True
    False ->
      case date.to_epoch_days(date.from_epoch_days(from)) == from {
        True -> round_trips(from + 1, to)
        False -> False
      }
  }
}

pub fn add_days_test() {
  assert date.add_days(Date(2026, 10, 6), 1) == Date(2026, 10, 7)
  assert date.add_days(Date(2026, 10, 31), 1) == Date(2026, 11, 1)
  assert date.add_days(Date(2026, 12, 31), 1) == Date(2027, 1, 1)
  assert date.add_days(Date(2026, 3, 1), -1) == Date(2026, 2, 28)
  assert date.add_days(Date(2024, 3, 1), -1) == Date(2024, 2, 29)
  assert date.add_days(Date(2026, 10, 6), 0) == Date(2026, 10, 6)
  assert date.add_days(Date(2026, 1, 1), 365) == Date(2027, 1, 1)
}

pub fn diff_and_compare_test() {
  assert date.diff_days(Date(2026, 10, 1), Date(2026, 10, 6)) == 5
  assert date.diff_days(Date(2026, 10, 6), Date(2026, 10, 1)) == -5
  assert date.compare(Date(2026, 10, 1), Date(2026, 10, 6)) == order.Lt
  assert date.compare(Date(2026, 10, 6), Date(2026, 10, 6)) == order.Eq
  assert date.compare(Date(2027, 1, 1), Date(2026, 12, 31)) == order.Gt
}

pub fn weekday_test() {
  assert date.weekday(Date(1970, 1, 1)) == Thursday
  assert date.weekday(Date(2026, 10, 6)) == date.Tuesday
  assert date.weekday(Date(2026, 10, 5)) == Monday
  assert date.weekday(Date(2026, 10, 9)) == Friday
  assert date.weekday(Date(2026, 10, 10)) == Saturday
  assert date.weekday(Date(2026, 10, 11)) == Sunday
  assert date.weekday(Date(1969, 12, 28)) == Sunday
}

pub fn start_of_week_test() {
  assert date.start_of_week(Date(2026, 10, 6)) == Date(2026, 10, 5)
  assert date.start_of_week(Date(2026, 10, 5)) == Date(2026, 10, 5)
  assert date.start_of_week(Date(2026, 10, 11)) == Date(2026, 10, 5)
  assert date.start_of_week(Date(2026, 1, 1)) == Date(2025, 12, 29)
}

pub fn local_date_applies_the_utc_offset_test() {
  assert date.local_date("2026-10-01 07:00:00.000Z", 0) == Ok(Date(2026, 10, 1))
  // 23:30 UTC is already the next day in UTC+2 (Swiss summer time), and still the same in UTC-5.
  assert date.local_date("2026-10-01 23:30:00.000Z", 120)
    == Ok(Date(2026, 10, 2))
  assert date.local_date("2026-10-01 23:30:00.000Z", -300)
    == Ok(Date(2026, 10, 1))
  // 00:30 UTC is still the previous day in UTC-5.
  assert date.local_date("2026-10-01 00:30:00.000Z", -300)
    == Ok(Date(2026, 9, 30))
  assert date.local_date("2026-12-31T23:00:00Z", 60) == Ok(Date(2027, 1, 1))
  assert date.local_date("2026-03-01 00:00:00.000Z", -1)
    == Ok(Date(2026, 2, 28))
}

pub fn local_date_rejects_bad_timestamps_test() {
  assert date.local_date("2026-10-01", 0) == Error(Nil)
  assert date.local_date("garbage garbage gar", 0) == Error(Nil)
  assert date.local_date("2026-10-01X07:00:00Z", 0) == Error(Nil)
  assert date.local_date("2026-10-01 25:00:00Z", 0) == Error(Nil)
  assert date.local_date("2026-10-01 07:61:00Z", 0) == Error(Nil)
}

pub fn timestamp_from_unix_test() {
  assert date.timestamp_from_unix(0) == "1970-01-01 00:00:00.000Z"
  assert date.timestamp_from_unix(1_759_065_612) == "2025-09-28 13:20:12.000Z"
  assert date.timestamp_from_unix(-1) == "1969-12-31 23:59:59.000Z"
}

pub fn from_unix_seconds_test() {
  assert date.from_unix_seconds(0, 0) == Date(1970, 1, 1)
  assert date.from_unix_seconds(86_399, 0) == Date(1970, 1, 1)
  assert date.from_unix_seconds(86_400, 0) == Date(1970, 1, 2)
  // 2026-10-06 23:30 UTC is already the 7th in UTC+2, and 2026-10-06 00:30 UTC is still the 5th in UTC-5.
  assert date.from_unix_seconds(1_791_329_400, 0) == Date(2026, 10, 6)
  assert date.from_unix_seconds(1_791_329_400, 120) == Date(2026, 10, 7)
  assert date.from_unix_seconds(1_791_246_600, -300) == Date(2026, 10, 5)
  assert date.from_unix_seconds(-1, 0) == Date(1969, 12, 31)
}

pub fn format_for_people_test() {
  assert date.format(Date(2026, 11, 2)) == "Mon 2 Nov 2026"
  assert date.format(Date(2026, 10, 6)) == "Tue 6 Oct 2026"
  assert date.format(Date(2024, 2, 29)) == "Thu 29 Feb 2024"
  assert date.format(Date(2027, 1, 1)) == "Fri 1 Jan 2027"
  assert date.format(Date(2026, 12, 31)) == "Thu 31 Dec 2026"
}

pub fn local_datetime_gives_date_and_clock_test() {
  assert date.local_datetime("2026-10-01 07:05:00.000Z", 0)
    == Ok(#(Date(2026, 10, 1), 7, 5))
  assert date.local_datetime("2026-10-01 23:30:00.000Z", 120)
    == Ok(#(Date(2026, 10, 2), 1, 30))
  assert date.local_datetime("2026-10-01 00:30:00.000Z", -300)
    == Ok(#(Date(2026, 9, 30), 19, 30))
  assert date.local_datetime("2026-12-31T23:00:00Z", 60)
    == Ok(#(Date(2027, 1, 1), 0, 0))
  assert date.local_datetime("2026-10-01", 0) == Error(Nil)
  assert date.local_datetime("2026-10-01 25:00:00Z", 0) == Error(Nil)
}

pub fn utc_timestamp_converts_local_time_test() {
  assert date.utc_timestamp(Date(2026, 10, 1), 7, 0, 0)
    == "2026-10-01 07:00:00.000Z"
  // 07:00 in UTC+2 is 05:00 UTC; 00:30 in UTC+2 is the evening before in UTC.
  assert date.utc_timestamp(Date(2026, 10, 1), 7, 0, 120)
    == "2026-10-01 05:00:00.000Z"
  assert date.utc_timestamp(Date(2026, 10, 1), 0, 30, 120)
    == "2026-09-30 22:30:00.000Z"
  // 22:00 in UTC-5 is already the next day in UTC.
  assert date.utc_timestamp(Date(2026, 10, 1), 22, 0, -300)
    == "2026-10-02 03:00:00.000Z"
  assert date.utc_timestamp(Date(2026, 1, 1), 0, 0, 60)
    == "2025-12-31 23:00:00.000Z"
  assert date.utc_timestamp(Date(2024, 2, 29), 23, 59, -60)
    == "2024-03-01 00:59:00.000Z"
}

pub fn local_and_utc_are_inverse_test() {
  // Every quarter hour of a day, in several offsets, survives a round trip.
  assert round_trips_through_utc([0, 60, 120, -300, 330, -570])
}

fn round_trips_through_utc(offsets: List(Int)) -> Bool {
  case offsets {
    [] -> True
    [offset, ..rest] -> all_minutes(offset, 0) && round_trips_through_utc(rest)
  }
}

fn all_minutes(offset: Int, minute_of_day: Int) -> Bool {
  case minute_of_day >= 1440 {
    True -> True
    False -> {
      let stamp =
        date.utc_timestamp(
          Date(2026, 3, 29),
          minute_of_day / 60,
          minute_of_day % 60,
          offset,
        )
      case date.local_datetime(stamp, offset) {
        Ok(#(Date(2026, 3, 29), h, m)) ->
          h == minute_of_day / 60
          && m == minute_of_day % 60
          && all_minutes(offset, minute_of_day + 15)
        _ -> False
      }
    }
  }
}
