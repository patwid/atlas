//// The Today screen: the workouts of the plans the user follows, around today, with what has been done.
//// Matching suggestions are shown as "looks done" and become stored matches only when the user confirms
//// or picks an activity (ADR 0026). Own state and messages; writes come back as `Action`s.

import atlas/activity_form.{type Row}
import atlas/collection
import atlas/date
import atlas/matching.{type Stored}
import atlas/outbox
import atlas/plan.{type Workout}
import atlas/random
import atlas/records
import atlas/route
import atlas/store
import atlas/today.{type Inputs, type Item}
import atlas/ui/html as wa
import atlas/units
import atlas/workout_form
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Which workout of which assignment: the same workout can be on the schedule twice.
pub type Key {
  Key(assignment_id: String, workout_id: String)
}

pub type Model {
  Model(
    /// Stored matches on the device, removed ones included.
    matches: List(Stored),
    loaded: Bool,
    /// The item whose activity list is open.
    choosing: Option(Key),
    /// The item whose "Unlink" was clicked once.
    confirming: Option(Key),
  )
}

pub type Msg {
  Refresh
  MatchesRead(Result(List(Dynamic), Nil))
  /// Accept the activity the matching rules suggest.
  ConfirmClicked(Key, String)
  ChooseClicked(Key)
  PickClicked(Key, String)
  UnlinkClicked(Key)
  UnlinkConfirmed(Key)
  CancelClicked
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model([], False, None, None)
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Matches, fn(result) {
      dispatch(MatchesRead(result))
    })
  })
}

pub fn update(
  model: Model,
  msg: Msg,
  inputs: Inputs,
) -> #(Model, Effect(Msg), List(Action)) {
  case msg {
    Refresh -> #(model, refresh(), [])

    MatchesRead(Ok(stored)) -> #(
      Model(
        ..model,
        matches: list.filter_map(stored, records.stored_match),
        loaded: True,
      ),
      effect.none(),
      [],
    )
    MatchesRead(Error(Nil)) -> #(model, effect.none(), [])

    ConfirmClicked(key, activity_id) -> link(model, inputs, key, activity_id)
    PickClicked(key, activity_id) -> link(model, inputs, key, activity_id)

    ChooseClicked(key) -> #(
      Model(..model, choosing: Some(key), confirming: None),
      effect.none(),
      [],
    )

    UnlinkClicked(key) -> #(
      Model(..model, confirming: Some(key), choosing: None),
      effect.none(),
      [],
    )

    UnlinkConfirmed(key) ->
      case stored_for(inputs, key) {
        Some(row) -> #(Model(..model, confirming: None), effect.none(), [
          Delete(row.id, row.updated),
        ])
        None -> #(Model(..model, confirming: None), effect.none(), [])
      }

    CancelClicked -> #(
      Model(..model, choosing: None, confirming: None),
      effect.none(),
      [],
    )
  }
}

/// Links an activity to a workout. A row for the activity that already exists (removed or not) is reused,
/// because an activity has one match row; the workout's previous link, if any, is removed.
fn link(
  model: Model,
  inputs: Inputs,
  key: Key,
  activity_id: String,
) -> #(Model, Effect(Msg), List(Action)) {
  let finished = Model(..model, choosing: None, confirming: None)
  let known =
    list.any(today.items(inputs), fn(item) { key_of(item) == key })
    && list.any(inputs.activities, fn(row) {
      row.activity.id == activity_id && row.owner_id == inputs.user_id
    })
  case known {
    False -> #(model, effect.none(), [])
    True -> {
      let previous = case stored_for(inputs, key) {
        Some(row) if row.match.activity_id != activity_id -> [
          Delete(row.id, row.updated),
        ]
        _ -> []
      }
      let target = [
        outbox.field_string("assignment", key.assignment_id),
        outbox.field_string("workout", key.workout_id),
      ]
      let write = case today.row_for_activity(inputs.matches, activity_id) {
        None -> [
          Create(
            random.new_id(),
            dict.from_list([
              outbox.field_string("owner", inputs.user_id),
              outbox.field_string("activity", activity_id),
              ..target
            ]),
          ),
        ]
        Some(row) -> {
          let same_place =
            row.match.assignment_id == key.assignment_id
            && row.match.workout_id == key.workout_id
          case same_place && !row.deleted {
            True -> []
            False -> [
              Edit(
                row.id,
                dict.from_list([outbox.field_bool("deleted", False), ..target]),
                row.updated,
              ),
            ]
          }
        }
      }
      #(finished, effect.none(), list.append(previous, write))
    }
  }
}

fn stored_for(inputs: Inputs, key: Key) -> Option(Stored) {
  case list.find(today.items(inputs), fn(item) { key_of(item) == key }) {
    Ok(item) -> item.stored
    Error(Nil) -> None
  }
}

fn key_of(item: Item) -> Key {
  Key(item.scheduled.assignment_id, item.scheduled.workout.id)
}

// VIEWS -------------------------------------------------------------------------------------------

pub fn view(model: Model, inputs: Inputs) -> Element(Msg) {
  let items = today.items(inputs)
  let sections = today.sections(items, inputs.today)
  html.section([class("today")], [
    html.h2([], [html.text(date.format(inputs.today))]),
    case inputs.assignments {
      [] ->
        html.p([class("muted")], [
          html.text(
            "You are not following a plan yet. Open a plan and start it to see your workouts here. ",
          ),
          html.a([attribute.href(route.to_path(route.Plans))], [
            html.text("Go to plans"),
          ]),
        ])
      _ ->
        html.div([], [
          group(
            "Today",
            sections.today,
            model,
            inputs,
            "Nothing planned for today.",
          ),
          group(
            "Coming up",
            sections.upcoming,
            model,
            inputs,
            "Nothing planned in the next "
              <> int.to_string(today.window_days)
              <> " days.",
          ),
          case sections.recent {
            [] -> element.none()
            recent ->
              group(
                "Last " <> int.to_string(today.window_days) <> " days",
                recent,
                model,
                inputs,
                "",
              )
          },
        ])
    },
  ])
}

fn group(
  heading: String,
  items: List(Item),
  model: Model,
  inputs: Inputs,
  empty: String,
) -> Element(Msg) {
  html.div([class("group")], [
    html.h3([], [html.text(heading)]),
    case items {
      [] -> html.p([class("muted")], [html.text(empty)])
      _ ->
        html.ul(
          [class("cards")],
          list.map(items, fn(item) { item_view(item, model, inputs) }),
        )
    },
  ])
}

fn item_view(item: Item, model: Model, inputs: Inputs) -> Element(Msg) {
  let w = item.scheduled.workout
  let key = key_of(item)
  html.li([class("item")], [
    html.div([], [
      html.strong([], [html.text(w.title)]),
      html.span([class("badge")], [html.text(workout_form.kind_label(w.kind))]),
      html.span([class("muted")], [
        html.text(
          " · " <> item.plan_title <> " · " <> date.format(item.scheduled.date),
        ),
      ]),
    ]),
    case targets(w) {
      "" -> element.none()
      text -> html.p([class("muted")], [html.text("Planned: " <> text)])
    },
    status_view(item, key, model, inputs),
    case model.choosing == Some(key) {
      True -> choosing_view(item, key, inputs)
      False -> element.none()
    },
  ])
}

fn status_view(
  item: Item,
  key: Key,
  model: Model,
  inputs: Inputs,
) -> Element(Msg) {
  case item.status {
    today.RestDay -> html.p([class("status")], [html.text("Rest day")])
    today.Planned ->
      html.div([], [
        html.p([class("status")], [html.text("To do")]),
        link_button("Link an activity", ChooseClicked(key)),
      ])
    today.Missed ->
      html.div([], [
        html.p([class("status missed")], [html.text("Missed")]),
        link_button("Link an activity", ChooseClicked(key)),
      ])
    today.Done(activity_id, False) ->
      html.div([], [
        html.p([class("status done")], [
          html.text("Looks done: " <> summary(inputs, activity_id)),
        ]),
        html.div([class("actions")], [
          wa.button(
            [
              attribute.type_("button"),
              attribute.attribute("variant", "brand"),
              event.on_click(ConfirmClicked(key, activity_id)),
            ],
            [html.text("Yes, that is it")],
          ),
          link_button("Choose another", ChooseClicked(key)),
        ]),
      ])
    today.Done(activity_id, True) ->
      html.div([], [
        html.p([class("status done")], [
          html.text("Done: " <> summary(inputs, activity_id)),
        ]),
        case model.confirming == Some(key) {
          False ->
            html.div([class("actions")], [
              link_button("Change", ChooseClicked(key)),
              link_button("Unlink", UnlinkClicked(key)),
            ])
          True ->
            html.div([class("actions")], [
              html.span([attribute.role("alert")], [
                html.text("Unlink this activity?"),
              ]),
              wa.button(
                [
                  attribute.type_("button"),
                  attribute.attribute("variant", "danger"),
                  event.on_click(UnlinkConfirmed(key)),
                ],
                [html.text("Yes, unlink")],
              ),
              link_button("Keep it", CancelClicked),
            ])
        },
      ])
  }
}

fn link_button(label: String, msg: Msg) -> Element(Msg) {
  wa.button(
    [
      attribute.type_("button"),
      attribute.attribute("variant", "neutral"),
      event.on_click(msg),
    ],
    [html.text(label)],
  )
}

fn choosing_view(item: Item, key: Key, inputs: Inputs) -> Element(Msg) {
  let candidates = today.candidates(inputs, item)
  html.div([class("choosing")], [
    case candidates {
      [] ->
        html.p([class("muted")], [
          html.text(
            "You have no activity on "
            <> date.format(item.scheduled.date)
            <> ". Add one in Activities first.",
          ),
        ])
      _ ->
        html.div([], [
          html.p([], [html.text("Which activity was it?")]),
          html.ul(
            [class("choices")],
            list.map(candidates, fn(row) {
              html.li([], [
                html.span([], [html.text(describe(row, inputs))]),
                wa.button(
                  [
                    attribute.type_("button"),
                    attribute.attribute("variant", "brand"),
                    event.on_click(PickClicked(key, row.activity.id)),
                  ],
                  [html.text("This one")],
                ),
              ])
            }),
          ),
        ])
    },
    link_button("Cancel", CancelClicked),
  ])
}

fn summary(inputs: Inputs, activity_id: String) -> String {
  case
    list.find(inputs.activities, fn(row) { row.activity.id == activity_id })
  {
    Ok(row) -> describe(row, inputs)
    Error(Nil) -> "an activity"
  }
}

/// `07:30 · Run · 8.50 km · 45:00`
fn describe(row: Row, inputs: Inputs) -> String {
  let a = row.activity
  let clock = case
    date.local_datetime(a.started_at, inputs.offset_at(a.started_at))
  {
    Ok(#(_, hour, minute)) -> pad2(hour) <> ":" <> pad2(minute)
    Error(Nil) -> ""
  }
  [
    clock,
    activity_form.sport_label(a.sport),
    case a.distance_m >. 0.0 {
      True -> units.format_distance_km(a.distance_m)
      False -> ""
    },
    case a.moving_time_s > 0 {
      True -> units.format_duration(a.moving_time_s)
      False -> ""
    },
  ]
  |> list.filter(fn(part) { part != "" })
  |> string.join(" · ")
}

fn targets(w: Workout) -> String {
  case w.distance_m, w.duration_s {
    Some(d), Some(t) ->
      units.format_distance_km(d) <> " · " <> units.format_duration(t)
    Some(d), None -> units.format_distance_km(d)
    None, Some(t) -> units.format_duration(t)
    None, None -> ""
  }
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}
