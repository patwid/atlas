//// Calendar dates without time zones, and the conversion from a UTC timestamp to a local date.
//// Training plans live on calendar days, so this is all the date handling the app needs.
//// Day counting follows Howard Hinnant's civil-date algorithms (proleptic Gregorian calendar).

import gleam/int
import gleam/order.{type Order}
import gleam/string

pub type Date {
  Date(year: Int, month: Int, day: Int)
}

pub type Weekday {
  Monday
  Tuesday
  Wednesday
  Thursday
  Friday
  Saturday
  Sunday
}

pub fn new(year: Int, month: Int, day: Int) -> Result(Date, Nil) {
  case
    month >= 1 && month <= 12 && day >= 1 && day <= days_in_month(year, month)
  {
    True -> Ok(Date(year, month, day))
    False -> Error(Nil)
  }
}

pub fn is_leap_year(year: Int) -> Bool {
  year % 4 == 0 && { year % 100 != 0 || year % 400 == 0 }
}

pub fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    2 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    4 | 6 | 9 | 11 -> 30
    _ -> 31
  }
}

/// Parses `YYYY-MM-DD` exactly (no other formats).
pub fn parse(text: String) -> Result(Date, Nil) {
  case string.split(text, "-") {
    [y, m, d] ->
      case
        string.length(y) == 4 && string.length(m) == 2 && string.length(d) == 2
      {
        True -> {
          use year <- try(int.parse(y))
          use month <- try(int.parse(m))
          use day <- try(int.parse(d))
          new(year, month, day)
        }
        False -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

pub fn to_string(date: Date) -> String {
  pad(date.year, 4) <> "-" <> pad(date.month, 2) <> "-" <> pad(date.day, 2)
}

/// Days since 1970-01-01 (negative before it).
pub fn to_epoch_days(date: Date) -> Int {
  let y = case date.month <= 2 {
    True -> date.year - 1
    False -> date.year
  }
  let era = floor_div(y, 400)
  let yoe = y - era * 400
  let shifted_month = case date.month > 2 {
    True -> date.month - 3
    False -> date.month + 9
  }
  let doy = { 153 * shifted_month + 2 } / 5 + date.day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146_097 + doe - 719_468
}

pub fn from_epoch_days(days: Int) -> Date {
  let z = days + 719_468
  let era = floor_div(z, 146_097)
  let doe = z - era * 146_097
  let yoe = { doe - doe / 1460 + doe / 36_524 - doe / 146_096 } / 365
  let doy = doe - { 365 * yoe + yoe / 4 - yoe / 100 }
  let mp = { 5 * doy + 2 } / 153
  let day = doy - { 153 * mp + 2 } / 5 + 1
  let month = case mp < 10 {
    True -> mp + 3
    False -> mp - 9
  }
  let year = case month <= 2 {
    True -> yoe + era * 400 + 1
    False -> yoe + era * 400
  }
  Date(year, month, day)
}

pub fn add_days(date: Date, days: Int) -> Date {
  from_epoch_days(to_epoch_days(date) + days)
}

/// Whole days from `from` to `to` (negative if `to` is earlier).
pub fn diff_days(from from: Date, to to: Date) -> Int {
  to_epoch_days(to) - to_epoch_days(from)
}

pub fn compare(a: Date, b: Date) -> Order {
  int.compare(to_epoch_days(a), to_epoch_days(b))
}

pub fn weekday(date: Date) -> Weekday {
  // 1970-01-01 was a Thursday.
  case modulo(to_epoch_days(date) + 3, 7) {
    0 -> Monday
    1 -> Tuesday
    2 -> Wednesday
    3 -> Thursday
    4 -> Friday
    5 -> Saturday
    _ -> Sunday
  }
}

/// The Monday of the week that contains `date`.
pub fn start_of_week(date: Date) -> Date {
  add_days(date, -modulo(to_epoch_days(date) + 3, 7))
}

/// The local date of a UTC timestamp such as `2026-10-01 07:00:00.000Z` or `2026-10-01T07:00:00Z`,
/// given the local offset from UTC in minutes (for example 120 for UTC+2).
pub fn local_date(
  timestamp: String,
  utc_offset_minutes: Int,
) -> Result(Date, Nil) {
  case string.length(timestamp) >= 16 {
    False -> Error(Nil)
    True -> {
      use date <- try(parse(string.slice(timestamp, 0, 10)))
      let separator = string.slice(timestamp, 10, 1)
      case separator == " " || separator == "T" {
        False -> Error(Nil)
        True -> {
          let hour = string.slice(timestamp, 11, 2)
          let minute = string.slice(timestamp, 14, 2)
          use h <- try(int.parse(hour))
          use m <- try(int.parse(minute))
          case h >= 0 && h <= 23 && m >= 0 && m <= 59 {
            False -> Error(Nil)
            True ->
              Ok(add_days(
                date,
                floor_div(h * 60 + m + utc_offset_minutes, 1440),
              ))
          }
        }
      }
    }
  }
}

fn pad(n: Int, width: Int) -> String {
  string.pad_start(int.to_string(n), width, "0")
}

fn floor_div(a: Int, b: Int) -> Int {
  case a >= 0 {
    True -> a / b
    False -> -{ { -a + b - 1 } / b }
  }
}

fn modulo(a: Int, b: Int) -> Int {
  a - floor_div(a, b) * b
}

fn try(
  result: Result(a, Nil),
  next: fn(a) -> Result(b, Nil),
) -> Result(b, Nil) {
  case result {
    Ok(value) -> next(value)
    Error(Nil) -> Error(Nil)
  }
}
