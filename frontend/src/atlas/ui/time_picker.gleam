//// Material 3's modal time picker with a dial (ADR 0054), opened from the clock button of a time field. The field
//// stays a native time input that can be typed in; the picker is a second way to fill it.
////
//// The clock is 24-hour: the outer ring holds 12 and 1 to 11, the inner ring 00 and 13 to 23, as on Android. Picking
//// an hour moves on to the minutes, which the dial offers in steps of 5; the arrow keys change the hour or minute
//// by one. The page keeps a `State`, wraps `Msg`, and calls `update`, which says when a time was picked.

import atlas/ui/button
import atlas/ui/dialog
import atlas/ui/icon
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Part {
  Hours
  Minutes
}

pub type State {
  Closed
  Open(hour: Int, minute: Int, part: Part)
}

pub type Msg {
  /// Open with the field's current text; an empty or unreadable field starts at 12:00.
  Opened(value: String)
  PartChosen(Part)
  HourPicked(Int)
  MinutePicked(Int)
  /// An arrow key changed the hour or minute on show by this much.
  KeyMoved(Int)
  Confirmed
  Dismissed
}

pub fn new() -> State {
  Closed
}

/// `id` is the dialog's id, unique in the page. The third value is the time picked, as the field's text (`07:30`),
/// when OK was pressed.
pub fn update(
  id: String,
  state: State,
  msg: Msg,
) -> #(State, Effect(Msg), Option(String)) {
  case msg, state {
    Opened(value), _ -> {
      let #(hour, minute) = case parse(value) {
        Ok(time) -> time
        Error(Nil) -> #(12, 0)
      }
      #(Open(hour, minute, Hours), dialog.show(id), None)
    }
    PartChosen(part), Open(h, m, _) -> #(Open(h, m, part), effect.none(), None)
    // As in M3, choosing the hour moves on to the minutes.
    HourPicked(h), Open(_, m, _) -> #(Open(h, m, Minutes), effect.none(), None)
    MinutePicked(m), Open(h, _, part) -> #(
      Open(h, m, part),
      effect.none(),
      None,
    )
    KeyMoved(by), Open(h, m, Hours) -> #(
      Open(wrap(h + by, 24), m, Hours),
      effect.none(),
      None,
    )
    KeyMoved(by), Open(h, m, Minutes) -> #(
      Open(h, wrap(m + by, 60), Minutes),
      effect.none(),
      None,
    )
    Confirmed, Open(h, m, _) -> #(Closed, effect.none(), Some(format(h, m)))
    Dismissed, _ -> #(Closed, effect.none(), None)
    _, _ -> #(state, effect.none(), None)
  }
}

fn wrap(value: Int, size: Int) -> Int {
  { value % size + size } % size
}

pub fn parse(text: String) -> Result(#(Int, Int), Nil) {
  case string.split(text, ":") {
    [h, m, ..] ->
      case int.parse(h), int.parse(m) {
        Ok(hour), Ok(minute)
          if hour >= 0 && hour < 24 && minute >= 0 && minute < 60
        -> Ok(#(hour, minute))
        _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

pub fn format(hour: Int, minute: Int) -> String {
  two(hour) <> ":" <> two(minute)
}

fn two(n: Int) -> String {
  string.pad_start(int.to_string(n), to: 2, with: "0")
}

/// Where an hour sits on the dial: its angle from 12 o'clock in degrees, and whether it is on the inner ring.
pub fn hour_position(hour: Int) -> #(Int, Bool) {
  #({ hour % 12 } * 30, hour == 0 || hour > 12)
}

/// The button that opens the picker, for the end of a time field.
pub fn trigger(id: String, on_open: msg) -> Element(msg) {
  button.icon(
    [
      attribute.type_("button"),
      class("field-trigger"),
      attribute.attribute("aria-haspopup", "dialog"),
      attribute.attribute("aria-controls", id),
      event.on_click(on_open),
    ],
    icon.Schedule,
    "Choose a time",
  )
}

pub fn view(id: String, state: State, to_msg: fn(Msg) -> msg) -> Element(msg) {
  let label_id = id <> "-label"
  html.dialog(
    [
      attribute.id(id),
      class("picker time-picker"),
      attribute.attribute("aria-labelledby", label_id),
      event.on("close", decode.success(to_msg(Dismissed))),
    ],
    case state {
      Closed -> []
      Open(hour, minute, part) -> [
        html.p([class("picker-label"), attribute.id(label_id)], [
          html.text("Select time"),
        ]),
        html.div([class("time-picker-fields")], [
          part_button(
            two(hour),
            "Hours",
            part == Hours,
            to_msg(PartChosen(Hours)),
          ),
          html.span([class("time-picker-colon")], [html.text(":")]),
          part_button(
            two(minute),
            "Minutes",
            part == Minutes,
            to_msg(PartChosen(Minutes)),
          ),
        ]),
        dial(hour, minute, part, to_msg),
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

fn part_button(
  text: String,
  label: String,
  active: Bool,
  msg: msg,
) -> Element(msg) {
  html.button(
    [
      attribute.type_("button"),
      class("time-picker-part"),
      attribute.classes([#("active", active)]),
      attribute.aria_label(label <> " " <> text),
      attribute.attribute("aria-pressed", case active {
        True -> "true"
        False -> "false"
      }),
      event.on_click(msg),
    ],
    [html.text(text)],
  )
}

fn dial(
  hour: Int,
  minute: Int,
  part: Part,
  to_msg: fn(Msg) -> msg,
) -> Element(msg) {
  let #(angle, inner) = case part {
    Hours -> hour_position(hour)
    Minutes -> #(minute * 6, False)
  }
  let numbers = case part {
    Hours ->
      list.map(list.append(hours_outer, hours_inner), fn(h) {
        let #(a, is_inner) = hour_position(h)
        number(
          two_or_plain(h),
          a,
          is_inner,
          h == hour,
          to_msg(HourPicked(h)),
          "hours",
        )
      })
    Minutes ->
      list.map(minutes, fn(m) {
        number(
          two(m),
          m * 6,
          False,
          m == minute,
          to_msg(MinutePicked(m)),
          "minutes",
        )
      })
  }
  html.div(
    [
      class("time-picker-dial"),
      attribute.role("group"),
      attribute.aria_label(case part {
        Hours -> "Hours"
        Minutes -> "Minutes"
      }),
      event.advanced("keydown", key_decoder(to_msg)),
    ],
    [
      html.div(
        [
          class("time-picker-hand"),
          attribute.classes([#("inner", inner)]),
          attribute.style("--angle", int.to_string(angle) <> "deg"),
        ],
        [],
      ),
      ..numbers
    ],
  )
}

const hours_outer = [12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

const hours_inner = [0, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]

const minutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

/// The inner ring's 00 keeps its zero; the other hours show as plain numbers.
fn two_or_plain(hour: Int) -> String {
  case hour {
    0 -> "00"
    _ -> int.to_string(hour)
  }
}

fn number(
  text: String,
  angle: Int,
  inner: Bool,
  selected: Bool,
  msg: msg,
  unit: String,
) -> Element(msg) {
  html.button(
    [
      attribute.type_("button"),
      class("time-picker-number"),
      attribute.classes([#("inner", inner), #("selected", selected)]),
      attribute.style("--angle", int.to_string(angle) <> "deg"),
      attribute.aria_label(text <> " " <> unit),
      attribute.attribute("aria-pressed", case selected {
        True -> "true"
        False -> "false"
      }),
      // The dial is one stop for Tab; the arrow keys change the value.
      attribute.attribute("tabindex", case selected {
        True -> "0"
        False -> "-1"
      }),
      event.on_click(msg),
    ],
    [html.text(text)],
  )
}

fn key_decoder(to_msg: fn(Msg) -> msg) -> decode.Decoder(event.Handler(msg)) {
  use key <- decode.field("key", decode.string)
  let by = case key {
    "ArrowUp" | "ArrowRight" -> Ok(1)
    "ArrowDown" | "ArrowLeft" -> Ok(-1)
    _ -> Error(Nil)
  }
  case by {
    Ok(n) ->
      decode.success(event.handler(
        dispatch: to_msg(KeyMoved(n)),
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
        "a key the dial does not use",
      )
  }
}
