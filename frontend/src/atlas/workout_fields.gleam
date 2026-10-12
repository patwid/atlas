//// The fields a workout and an activity share (ADR 0121): the kind, the zone, the parts of intervals and the warm-up
//// and cool-down of a race, the distance and duration, and the notes. The forms that use them own their messages:
//// they pass in what each field sends. Element IDs start with the form's `prefix`, `workout` or `activity`.

import atlas/plan.{type Kind}
import atlas/ui/button
import atlas/ui/choice
import atlas/ui/field
import atlas/ui/icon
import atlas/workout_form.{type Form, type Part}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// What each field sends when it changes.
pub type Events(msg) {
  Events(
    kind: fn(String) -> msg,
    zone: fn(String) -> msg,
    distance: fn(String) -> msg,
    duration: fn(String) -> msg,
    description: fn(String) -> msg,
    /// A zone, race goal, intensity, distance or time of a part (ADR 0116, 0118).
    segment: fn(Part, workout_form.SegmentField, String) -> msg,
    /// The repetitions of a set, from 0.
    reps: fn(Int, String) -> msg,
    set_added: msg,
    set_removed: fn(Int) -> msg,
  )
}

/// Shows a field's problem under it (ADR 0059): the help of a field and the name its problem gives it.
pub type On =
  fn(field.Help, String) -> field.Help

/// `set1_reps` as an element ID: `workout-set1-reps`.
pub fn field_id(prefix: String, name: String) -> String {
  prefix <> "-" <> string.replace(name, "_", "-")
}

/// `#("run", "Run")` for each of `kinds`.
pub fn kind_options(kinds: List(Kind)) -> List(#(String, String)) {
  list.map(kinds, fn(kind) {
    #(plan.kind_to_string(kind), workout_form.kind_label(kind))
  })
}

pub fn kind_field(
  value: String,
  options: List(#(String, String)),
  events: Events(msg),
) -> Element(msg) {
  choice.chips("kind", "Kind", value, options, events.kind)
}

/// What is run, for the form's kind: a race's warm-up, the zone, the parts of intervals, the distance and duration,
/// and a race's cool-down (ADR 0105, 0116, 0119). `distance_help` says whether a distance is needed.
pub fn targets(
  form: Form,
  prefix: String,
  distance_help: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  element.fragment([
    // A race is warmed up for before it (ADR 0119).
    case form.kind {
      plan.Race ->
        segment_group("Warm-up", form, workout_form.Warmup, prefix, on, events)
      _ -> element.none()
    },
    // A rest day has no zone (ADR 0105); each part of an interval workout has its own (ADR 0116).
    case form.kind {
      plan.Rest | plan.Interval -> element.none()
      _ ->
        field.choose(
          prefix <> "-zone",
          "Zone",
          on(field.help("Optional"), "zone"),
          [attribute.name("zone"), event.on_change(events.zone)],
          form.zone,
          zone_options(),
        )
    },
    case form.kind {
      plan.Interval -> interval_fields(form, prefix, on, events)
      _ -> element.none()
    },
    distance_and_duration(form, prefix, distance_help, on, events),
    case form.kind {
      plan.Race ->
        segment_group(
          "Cool-down",
          form,
          workout_form.Cooldown,
          prefix,
          on,
          events,
        )
      _ -> element.none()
    },
  ])
}

pub fn distance_and_duration(
  form: Form,
  prefix: String,
  distance_help: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  html.div([class("row")], [
    field.text(
      prefix <> "-distance",
      "Distance",
      on(field.Help(distance_help, "km", None), "distance"),
      [
        attribute.type_("text"),
        attribute.attribute("inputmode", "decimal"),
        attribute.name("distance"),
        attribute.value(form.distance_km),
        event.on_input(events.distance),
      ],
    ),
    field.text(
      prefix <> "-duration",
      "Duration",
      on(field.help("Minutes, or hours and minutes: 45 or 1:30"), "duration"),
      [
        attribute.type_("text"),
        attribute.name("duration"),
        attribute.value(form.duration),
        event.on_input(events.duration),
      ],
    ),
  ])
}

pub fn notes(
  form: Form,
  prefix: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  field.area(
    prefix <> "-description",
    "Notes",
    on(field.help("Optional"), "description"),
    [
      attribute.name("description"),
      attribute.rows(3),
      event.on_input(events.description),
    ],
    form.description,
  )
}

fn zone_options() -> List(#(String, String)) {
  [
    #("", "No zone"),
    ..list.map(workout_form.zones, fn(n) {
      #(int.to_string(n), workout_form.zone_label(n))
    })
  ]
}

/// The parts of an interval workout, shown only for that kind (ADR 0104, 0116): a warm-up, its sets and a
/// cool-down, each with a zone, a distance and a time.
fn interval_fields(
  form: Form,
  prefix: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  let several = list.length(form.sets) > 1
  element.fragment([
    segment_group("Warm-up", form, workout_form.Warmup, prefix, on, events),
    element.fragment(
      list.index_map(form.sets, fn(set, index) {
        set_group(set, index, several, form, prefix, on, events)
      }),
    ),
    html.div([class("interval-add-set")], [
      button.outlined(
        [attribute.type_("button"), event.on_click(events.set_added)],
        [icon.view(icon.Add), html.text("Add set")],
      ),
    ]),
    segment_group("Cool-down", form, workout_form.Cooldown, prefix, on, events),
    interval_totals(form, prefix),
  ])
}

fn segment_group(
  legend: String,
  form: Form,
  part: Part,
  prefix: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  html.fieldset([class("interval-part")], [
    html.legend([], [html.text(legend)]),
    segment_fields(form, part, "", prefix, on, events),
  ])
}

fn set_group(
  set: workout_form.SetForm,
  index: Int,
  several: Bool,
  form: Form,
  prefix: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  let number = int.to_string(index + 1)
  let reps = workout_form.reps_field_name(index)
  html.fieldset([class("interval-part")], [
    html.legend([], [html.text("Set " <> number)]),
    html.div([class("row")], [
      field.text(
        field_id(prefix, reps),
        "Repetitions",
        on(field.help("For example 6"), reps),
        [
          attribute.type_("text"),
          attribute.attribute("inputmode", "numeric"),
          attribute.name(reps),
          attribute.value(set.reps),
          event.on_input(events.reps(index, _)),
        ],
      ),
    ]),
    target_choice(form, workout_form.Work(index), events),
    segment_fields(form, workout_form.Work(index), "Rep ", prefix, on, events),
    intensity_slider(form, workout_form.Work(index), prefix, on, events),
    segment_fields(
      form,
      workout_form.Recovery(index),
      "Recovery ",
      prefix,
      on,
      events,
    ),
    case several {
      True ->
        html.div([class("interval-remove-set")], [
          button.text(
            [
              attribute.type_("button"),
              event.on_click(events.set_removed(index)),
            ],
            [html.text("Remove set " <> number)],
          ),
        ])
      False -> element.none()
    },
  ])
}

/// A part's zone, distance and time. A warm-up and a cool-down are typed in kilometres and minutes, a rep and a
/// recovery in metres and seconds (ADR 0116).
fn segment_fields(
  form: Form,
  part: Part,
  label: String,
  prefix: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  let segment = workout_form.segment(form, part)
  let name = workout_form.segment_field_name(part, _)
  let #(unit, time_help) = case part {
    workout_form.Warmup | workout_form.Cooldown -> #(
      "km",
      "Minutes, or hours and minutes: 15 or 1:30",
    )
    _ -> #("m", "Seconds, or minutes and seconds: 90 or 1:30")
  }
  let distance_help = case part {
    workout_form.Work(_) -> "Distance, time or both"
    _ -> "Optional"
  }
  let capital = case label {
    "" -> fn(text) { text }
    _ -> fn(text) { label <> string.lowercase(text) }
  }
  html.div([class("row")], [
    case workout_form.target(segment) {
      "goal" -> goal_select(form, part, prefix, on, events)
      _ ->
        field.choose(
          field_id(prefix, name(workout_form.ZoneField)),
          capital("Zone"),
          on(field.plain, name(workout_form.ZoneField)),
          [
            attribute.name(name(workout_form.ZoneField)),
            event.on_change(events.segment(part, workout_form.ZoneField, _)),
          ],
          segment.zone,
          zone_options(),
        )
    },
    field.text(
      field_id(prefix, name(workout_form.DistanceField)),
      capital("Distance"),
      on(
        field.Help(distance_help, unit, None),
        name(workout_form.DistanceField),
      ),
      [
        attribute.type_("text"),
        attribute.attribute("inputmode", "decimal"),
        attribute.name(name(workout_form.DistanceField)),
        attribute.value(segment.distance),
        event.on_input(events.segment(part, workout_form.DistanceField, _)),
      ],
    ),
    field.text(
      field_id(prefix, name(workout_form.TimeField)),
      capital("Time"),
      on(field.help(time_help), name(workout_form.TimeField)),
      [
        attribute.type_("text"),
        attribute.name(name(workout_form.TimeField)),
        attribute.value(segment.time),
        event.on_input(events.segment(part, workout_form.TimeField, _)),
      ],
    ),
  ])
}

/// Whether a rep is run at a zone or at a race goal (ADR 0118, 0120); a zone unless chosen otherwise. Only asked when
/// the athlete has goals or the rep has one.
fn target_choice(form: Form, part: Part, events: Events(msg)) -> Element(msg) {
  let segment = workout_form.segment(form, part)
  case form.goals, segment.goal {
    [], "" -> element.none()
    _, _ ->
      html.div([class("row")], [
        choice.segmented(
          workout_form.segment_field_name(part, workout_form.TargetField),
          "Rep run at",
          workout_form.target(segment),
          [#("zone", "Zone"), #("goal", "Race goal")],
          events.segment(part, workout_form.TargetField, _),
        ),
      ])
  }
}

/// The race goal a rep is run at (ADR 0118), in the place of its zone.
fn goal_select(
  form: Form,
  part: Part,
  prefix: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  let name = workout_form.segment_field_name(part, workout_form.GoalField)
  field.choose(
    field_id(prefix, name),
    "Rep race goal",
    on(field.plain, name),
    [
      attribute.name(name),
      event.on_change(events.segment(part, workout_form.GoalField, _)),
    ],
    workout_form.segment(form, part).goal,
    list.map(form.goals, fn(g) { #(g.id, workout_form.goal_label(g)) }),
  )
}

/// The intensity of a rep run at a race goal, a slider from 1 to 100 % of the goal's speed (ADR 0118, 0120).
fn intensity_slider(
  form: Form,
  part: Part,
  prefix: String,
  on: On,
  events: Events(msg),
) -> Element(msg) {
  let segment = workout_form.segment(form, part)
  let name = workout_form.segment_field_name(part, workout_form.IntensityField)
  let id = field_id(prefix, name)
  case workout_form.target(segment) {
    "goal" -> {
      let level = case int.parse(string.trim(segment.intensity)) {
        Ok(n) -> int.clamp(n, 1, 100)
        Error(_) -> 100
      }
      let text = int.to_string(level) <> " %"
      let help = on(field.help("100 % is the goal's pace"), name)
      html.div(
        [
          class("intensity-setting"),
          attribute.classes([#("has-error", help.error != None)]),
        ],
        [
          html.div([class("intensity-heading")], [
            html.label([attribute.for(id)], [html.text("Rep intensity")]),
            html.output([attribute.for(id), class("intensity-value")], [
              html.text(text),
            ]),
          ]),
          html.div([class("intensity-control")], [
            html.input([
              attribute.id(id),
              attribute.type_("range"),
              attribute.name(name),
              attribute.attribute("min", "1"),
              attribute.attribute("max", "100"),
              attribute.attribute("step", "1"),
              attribute.value(int.to_string(level)),
              attribute.attribute("aria-valuetext", text),
              attribute.attribute("aria-describedby", id <> "-help"),
              // How far the active track reaches, for browsers that cannot draw it themselves (ADR 0051).
              attribute.style(
                "--fill",
                int.to_string({ level - 1 } * 100 / 99) <> "%",
              ),
              event.on_input(events.segment(
                part,
                workout_form.IntensityField,
                _,
              )),
            ]),
          ]),
          html.p(
            [
              attribute.id(id <> "-help"),
              class("md-field-supporting"),
              ..case help.error {
                Some(_) -> [attribute.role("alert")]
                None -> []
              }
            ],
            [
              html.text(case help.error {
                Some(message) -> message
                None -> help.supporting
              }),
            ],
          ),
        ],
      )
    }
    _ -> element.none()
  }
}

/// All the parts together, worked out and read-only (ADR 0106, 0116). The fields have no name, so they are not
/// part of what is saved.
fn interval_totals(form: Form, prefix: String) -> Element(msg) {
  case workout_form.interval_totals(form) {
    #(None, None) -> element.none()
    #(distance, time) ->
      html.div([class("row")], [
        field.text(
          prefix <> "-total-distance",
          "Total distance",
          field.Help("Parts with a distance", "km", None),
          [
            attribute.type_("text"),
            attribute.readonly(True),
            attribute.value(case distance {
              Some(m) -> workout_form.format_km(m)
              None -> ""
            }),
          ],
        ),
        field.text(
          prefix <> "-total-time",
          "Total time",
          field.help("Parts with a time"),
          [
            attribute.type_("text"),
            attribute.readonly(True),
            attribute.value(case time {
              Some(s) -> workout_form.format_rep_time(s)
              None -> ""
            }),
          ],
        ),
      ])
  }
}
