//// Material 3's modal date picker (ADR 0054), opened from the calendar button of a date field. The field itself stays
//// a native date input that can be typed in; the picker is a second way to fill it.
////
//// A page keeps a `State` per picker, wraps `Msg` in its own message, and calls `update`, which says when a date was
//// picked. The dialog is a native `<dialog>` (opened with `atlas/ui/dialog.show`), so Escape and a click outside
//// close it like the app's other dialogs. The days are a grid with one focusable day: the arrow keys move a day or a
//// week, Page Up and Page Down a month, Home and End to the week's ends.

import atlas/date.{type Date}
import atlas/ui/button
import atlas/ui/dialog
import atlas/ui/focus
import atlas/ui/icon
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type State {
  Closed
  /// `year` and `month` are the month on show; `draft` is the date chosen so far, kept until OK.
  Open(year: Int, month: Int, draft: Date)
}

pub type Msg {
  /// Open with the field's current text, or `today` when it holds no date.
  Opened(value: String, today: Date)
  MonthMoved(by: Int)
  DayPicked(Date)
  /// A key on the grid of days moved the date by this many days or months.
  KeyMoved(Move)
  Confirmed
  /// The dialog closed, whichever way.
  Dismissed
}

pub type Move {
  Days(Int)
  Months(Int)
  WeekStart
  WeekEnd
}

pub fn new() -> State {
  Closed
}

/// `id` is the dialog's id, unique in the page. The third value is the date picked, as the field's text
/// (`2026-10-05`), when OK was pressed.
pub fn update(
  id: String,
  state: State,
  msg: Msg,
) -> #(State, Effect(Msg), Option(String)) {
  case msg, state {
    Opened(value, today), _ -> {
      let draft = case date.parse(value) {
        Ok(d) -> d
        Error(Nil) -> today
      }
      #(
        Open(draft.year, draft.month, draft),
        effect.batch([dialog.show(id), focus.soon(day_id(id, draft))]),
        None,
      )
    }
    MonthMoved(by), Open(year, month, draft) -> {
      let #(y, m) = add_months(year, month, by)
      #(Open(y, m, draft), effect.none(), None)
    }
    DayPicked(d), Open(..) -> #(Open(d.year, d.month, d), effect.none(), None)
    KeyMoved(move), Open(_, _, draft) -> {
      let moved = apply(draft, move)
      #(
        Open(moved.year, moved.month, moved),
        focus.soon(day_id(id, moved)),
        None,
      )
    }
    Confirmed, Open(_, _, draft) -> #(
      Closed,
      effect.none(),
      Some(date.to_string(draft)),
    )
    Dismissed, _ -> #(Closed, effect.none(), None)
    _, _ -> #(state, effect.none(), None)
  }
}

fn apply(d: Date, move: Move) -> Date {
  case move {
    Days(n) -> date.add_days(d, n)
    Months(n) -> {
      let #(y, m) = add_months(d.year, d.month, n)
      date.Date(y, m, int.min(d.day, date.days_in_month(y, m)))
    }
    WeekStart -> date.start_of_week(d)
    WeekEnd -> date.add_days(date.start_of_week(d), 6)
  }
}

fn add_months(year: Int, month: Int, by: Int) -> #(Int, Int) {
  let index = year * 12 + month - 1 + by
  #(floor_div(index, 12), index - floor_div(index, 12) * 12 + 1)
}

fn floor_div(a: Int, b: Int) -> Int {
  case a % b < 0 {
    True -> a / b - 1
    False -> a / b
  }
}

/// The month as weeks from Monday to Sunday; days outside the month are `None`.
pub fn weeks(year: Int, month: Int) -> List(List(Option(Date))) {
  let first = date.Date(year, month, 1)
  let lead = date.diff_days(from: date.start_of_week(first), to: first)
  let days = date.days_in_month(year, month)
  let cells =
    list.append(
      list.repeat(None, lead),
      list.map(days_of(days), fn(day) { Some(date.Date(year, month, day)) }),
    )
  let trail = { 7 - list.length(cells) % 7 } % 7
  list.sized_chunk(list.append(cells, list.repeat(None, trail)), 7)
}

/// 1 to `days`, in order.
fn days_of(days: Int) -> List(Int) {
  int.range(from: days, to: 0, with: [], run: list.prepend)
}

/// The button that opens the picker, for the end of a date field.
pub fn trigger(id: String, on_open: msg) -> Element(msg) {
  button.icon(
    [
      attribute.type_("button"),
      class("field-trigger"),
      attribute.attribute("aria-haspopup", "dialog"),
      attribute.attribute("aria-controls", id),
      event.on_click(on_open),
    ],
    icon.CalendarToday,
    "Choose a date",
  )
}

pub fn view(
  id: String,
  state: State,
  today: Date,
  to_msg: fn(Msg) -> msg,
) -> Element(msg) {
  let headline_id = id <> "-headline"
  html.dialog(
    [
      attribute.id(id),
      class("picker date-picker"),
      attribute.attribute("aria-labelledby", headline_id),
      event.on("close", decode.success(to_msg(Dismissed))),
    ],
    case state {
      Closed -> []
      Open(year, month, draft) -> [
        html.p([class("picker-label")], [html.text("Select date")]),
        html.h2([class("picker-headline"), attribute.id(headline_id)], [
          html.text(headline(draft)),
        ]),
        html.div([class("date-picker-month")], [
          html.span(
            [
              class("date-picker-title"),
              attribute.attribute("aria-live", "polite"),
            ],
            [
              html.text(month_name(month) <> " " <> int.to_string(year)),
            ],
          ),
          button.icon(
            [attribute.type_("button"), event.on_click(to_msg(MonthMoved(-1)))],
            icon.ChevronLeft,
            "Previous month",
          ),
          button.icon(
            [attribute.type_("button"), event.on_click(to_msg(MonthMoved(1)))],
            icon.ChevronRight,
            "Next month",
          ),
        ]),
        grid(id, year, month, draft, today, to_msg),
        html.form(
          [
            attribute.attribute("method", "dialog"),
            class("actions picker-actions"),
          ],
          [
            button.text([attribute.type_("submit")], [html.text("Cancel")]),
            button.text(
              [attribute.type_("submit"), event.on_click(to_msg(Confirmed))],
              [html.text("OK")],
            ),
          ],
        ),
      ]
    },
  )
}

fn grid(
  id: String,
  year: Int,
  month: Int,
  draft: Date,
  today: Date,
  to_msg: fn(Msg) -> msg,
) -> Element(msg) {
  // The one day reachable with Tab: the chosen day when it is in this month, else the 1st.
  let focusable = case draft.year == year && draft.month == month {
    True -> draft
    False -> date.Date(year, month, 1)
  }
  html.table(
    [
      class("date-picker-grid"),
      attribute.role("grid"),
      attribute.aria_label(month_name(month) <> " " <> int.to_string(year)),
      event.advanced("keydown", key_decoder(to_msg)),
    ],
    [
      html.thead([], [
        html.tr(
          [],
          list.map(
            [
              #("M", "Monday"),
              #("T", "Tuesday"),
              #("W", "Wednesday"),
              #("T", "Thursday"),
              #("F", "Friday"),
              #("S", "Saturday"),
              #("S", "Sunday"),
            ],
            fn(day) {
              html.th(
                [attribute.scope("col"), attribute.attribute("abbr", day.1)],
                [html.text(day.0)],
              )
            },
          ),
        ),
      ]),
      html.tbody(
        [],
        list.map(weeks(year, month), fn(week) {
          html.tr(
            [],
            list.map(week, fn(cell) {
              case cell {
                None -> html.td([], [])
                Some(d) ->
                  html.td([attribute.role("gridcell")], [
                    html.button(
                      [
                        attribute.type_("button"),
                        attribute.id(day_id(id, d)),
                        class("date-picker-day"),
                        attribute.classes([
                          #("selected", d == draft),
                          #("today", d == today),
                        ]),
                        attribute.attribute("aria-selected", case d == draft {
                          True -> "true"
                          False -> "false"
                        }),
                        case d == today {
                          True -> attribute.attribute("aria-current", "date")
                          False -> attribute.none()
                        },
                        attribute.aria_label(date.format(d)),
                        attribute.attribute("tabindex", case d == focusable {
                          True -> "0"
                          False -> "-1"
                        }),
                        event.on_click(to_msg(DayPicked(d))),
                      ],
                      [html.text(int.to_string(d.day))],
                    ),
                  ])
              }
            }),
          )
        }),
      ),
    ],
  )
}

fn key_decoder(to_msg: fn(Msg) -> msg) -> decode.Decoder(event.Handler(msg)) {
  use key <- decode.field("key", decode.string)
  let move = case key {
    "ArrowLeft" -> Ok(Days(-1))
    "ArrowRight" -> Ok(Days(1))
    "ArrowUp" -> Ok(Days(-7))
    "ArrowDown" -> Ok(Days(7))
    "PageUp" -> Ok(Months(-1))
    "PageDown" -> Ok(Months(1))
    "Home" -> Ok(WeekStart)
    "End" -> Ok(WeekEnd)
    _ -> Error(Nil)
  }
  case move {
    Ok(m) ->
      decode.success(event.handler(
        dispatch: to_msg(KeyMoved(m)),
        prevent_default: True,
        stop_propagation: False,
      ))
    Error(Nil) ->
      decode.failure(
        event.handler(
          dispatch: to_msg(Dismissed),
          prevent_default: False,
          stop_propagation: False,
        ),
        "a key the grid does not use",
      )
  }
}

fn day_id(id: String, d: Date) -> String {
  id <> "-" <> date.to_string(d)
}

/// `Mon, 5 Oct`, as M3's picker headline shows the chosen date.
fn headline(d: Date) -> String {
  date.weekday_short(date.weekday(d))
  <> ", "
  <> int.to_string(d.day)
  <> " "
  <> date.month_short(d.month)
}

pub fn month_name(month: Int) -> String {
  case month {
    1 -> "January"
    2 -> "February"
    3 -> "March"
    4 -> "April"
    5 -> "May"
    6 -> "June"
    7 -> "July"
    8 -> "August"
    9 -> "September"
    10 -> "October"
    11 -> "November"
    _ -> "December"
  }
}
