//// The Home screen: the workouts of the plans the user follows, around today, with what has been done.
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
import atlas/timer
import atlas/today.{type Inputs, type Item}
import atlas/ui/button
import atlas/ui/chip
import atlas/ui/empty
import atlas/ui/icon
import atlas/ui/layout
import atlas/ui/menu
import atlas/ui/snackbar
import atlas/ui/undo
import atlas/units
import atlas/workout_form
import gleam/dict
import gleam/dynamic.{type Dynamic}
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
    /// The link just removed, for Undo (ADR 0056): the snackbar's number, the item and its activity.
    unlinked: Option(#(Int, Key, String)),
    /// How many such snackbars have been shown, so a timer only closes its own.
    unlinks: Int,
  )
}

pub type Msg {
  Refresh
  MatchesRead(Result(List(Dynamic), Nil))
  /// Accept the activity the matching rules suggest.
  ConfirmClicked(Key, String)
  ChooseClicked(Key)
  PickClicked(Key, String)
  /// Unlinks at once; Undo links the same activity again (ADR 0056).
  UnlinkClicked(Key)
  UnlinkUndone
  UnlinkNoticeExpired(Int)
  CancelClicked
}

pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
}

pub fn new() -> Model {
  Model([], False, None, None, 0)
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
      Model(..model, choosing: Some(key)),
      effect.none(),
      [],
    )

    UnlinkClicked(key) ->
      case stored_for(inputs, key) {
        Some(row) -> {
          let n = model.unlinks + 1
          #(
            Model(
              ..model,
              unlinked: Some(#(n, key, row.match.activity_id)),
              unlinks: n,
              choosing: None,
            ),
            timer.after(undo.seconds, UnlinkNoticeExpired(n)),
            [Delete(row.id, row.updated)],
          )
        }
        None -> #(model, effect.none(), [])
      }

    UnlinkUndone ->
      case model.unlinked {
        Some(#(_, key, activity_id)) ->
          link(Model(..model, unlinked: None), inputs, key, activity_id)
        None -> #(model, effect.none(), [])
      }

    UnlinkNoticeExpired(n) ->
      case model.unlinked {
        Some(#(shown, _, _)) if shown == n -> #(
          Model(..model, unlinked: None),
          effect.none(),
          [],
        )
        _ -> #(model, effect.none(), [])
      }

    CancelClicked -> #(Model(..model, choosing: None), effect.none(), [])
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
  let finished = Model(..model, choosing: None)
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
  html.section([class("home")], [
    case model.unlinked {
      Some(#(n, _, _)) ->
        snackbar.view(
          "Activity unlinked",
          Some(snackbar.Act("Undo", UnlinkUndone)),
          UnlinkNoticeExpired(n),
        )
      None -> element.none()
    },
    case inputs.assignments {
      [] ->
        empty.view(
          icon.Home,
          "You are not following a plan yet",
          "Open a plan and start it to see your workouts here.",
          Some(empty.link(route.to_path(route.Plans), "Go to plans")),
        )
      _ ->
        html.div([], [
          // Newest first, from the end of the week ahead down to the last seven days (ADR 0082).
          group(
            "Coming up",
            newest_first(sections.upcoming),
            model,
            inputs,
            "Nothing planned in the next "
              <> int.to_string(today.window_days)
              <> " days.",
          ),
          group(
            "Today · " <> date.format(inputs.today),
            sections.today,
            model,
            inputs,
            "Nothing planned for today.",
          ),
          case sections.recent {
            [] -> element.none()
            recent ->
              group(
                "Last " <> int.to_string(today.window_days) <> " days",
                newest_first(recent),
                model,
                inputs,
                "",
              )
          },
        ])
    },
  ])
}

/// Items ordered by day, newest first. A day's workouts keep their order: plan, then position.
fn newest_first(items: List(Item)) -> List(Item) {
  items
  |> list.chunk(fn(item) { item.scheduled.date })
  |> list.reverse
  |> list.flatten
}

fn group(
  heading: String,
  items: List(Item),
  model: Model,
  inputs: Inputs,
  empty: String,
) -> Element(Msg) {
  html.div([class("group")], [
    layout.subheader(heading),
    case items {
      [] -> html.p([class("muted")], [html.text(empty)])
      _ ->
        layout.list(
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
      // In a chip row, which keeps it apart from the title as on the other lists.
      chip.row([chip.label(workout_form.kind_label(w.kind))]),
      case details(item, inputs) {
        "" -> element.none()
        text -> html.span([class("muted")], [html.text(" · " <> text)])
      },
    ]),
    case targets(w) {
      "" -> element.none()
      text -> html.p([class("muted")], [html.text("Planned: " <> text)])
    },
    status_view(item, key, inputs),
    case model.choosing == Some(key) {
      True -> choosing_view(item, key, inputs)
      False -> element.none()
    },
  ])
}

/// The plan, when the user follows more than one, and the day, unless it is today: the group heading says that.
fn details(item: Item, inputs: Inputs) -> String {
  let plans =
    inputs.assignments
    |> list.filter(fn(row) { row.assignment.athlete_id == inputs.user_id })
    |> list.map(fn(row) { row.assignment.plan_id })
    |> list.unique
  [
    case plans {
      [_, _, ..] -> item.plan_title
      _ -> ""
    },
    case item.scheduled.date == inputs.today {
      True -> ""
      False -> date.format(item.scheduled.date)
    },
  ]
  |> list.filter(fn(part) { part != "" })
  |> string.join(" · ")
}

/// The day's state as a chip in the color of its kind, then what was run, if anything (ADR 0048), then the action
/// that belongs to it, on the same line (ADR 0081).
fn status(
  kind: String,
  symbol: Option(icon.Icon),
  label: String,
  details: String,
  action: Element(Msg),
) -> Element(Msg) {
  html.p([class("status")], [
    html.span([class("status-chip status-" <> kind)], [
      case symbol {
        Some(s) -> icon.view(s)
        None -> element.none()
      },
      html.text(label),
    ]),
    case details {
      "" -> element.none()
      text -> html.span([class("status-details")], [html.text(text)])
    },
    action,
  ])
}

fn status_view(item: Item, key: Key, inputs: Inputs) -> Element(Msg) {
  case item.status {
    today.RestDay -> status("rest", None, "Rest day", "", element.none())
    // Only activities of the workout's own day can be linked, so a workout still to come has nothing to offer.
    today.Planned ->
      status(
        "planned",
        Some(icon.Pending),
        "To do",
        "",
        case item.scheduled.date == inputs.today {
          True -> link_button(key)
          False -> element.none()
        },
      )
    today.Missed ->
      status("missed", Some(icon.Close), "Missed", "", link_button(key))
    today.Done(activity_id, False) ->
      html.div([], [
        status(
          "suggested",
          Some(icon.Check),
          "Looks done",
          summary(inputs, activity_id),
          element.none(),
        ),
        layout.actions([
          button.filled(
            [
              attribute.type_("button"),
              event.on_click(ConfirmClicked(key, activity_id)),
            ],
            [html.text("Confirm")],
          ),
          button.text(
            [attribute.type_("button"), event.on_click(ChooseClicked(key))],
            [html.text("Choose another")],
          ),
        ]),
      ])
    today.Done(activity_id, True) ->
      html.div([], [
        status(
          "done",
          Some(icon.Check),
          "Done",
          summary(inputs, activity_id),
          element.none(),
        ),
        // Changing or removing a confirmed link is rare: a menu, as an activity's actions are (ADR 0056).
        menu.view(
          "home-menu-" <> key.assignment_id <> "-" <> key.workout_id,
          "More for " <> item.scheduled.workout.title,
          [
            menu.Item(icon.Edit, "Change activity", ChooseClicked(key)),
            menu.Item(icon.Close, "Unlink", UnlinkClicked(key)),
          ],
        ),
      ])
  }
}

/// Linking is a text button with an icon (ADR 0081): low emphasis, so it does not look like the status chip
/// beside it, and a list of missed workouts is not a column of buttons.
fn link_button(key: Key) -> Element(Msg) {
  button.text(
    [
      attribute.type_("button"),
      class("status-action"),
      event.on_click(ChooseClicked(key)),
    ],
    [icon.view(icon.Link), html.text("Link activity")],
  )
}

/// Choosing the activity is M3's simple dialog (ADR 0062): the activities are its choices, and a choice is taken
/// at once. It opens when drawn (`data-open`, see `atlas/ui/interaction`); Escape and Cancel close it.
fn choosing_view(item: Item, key: Key, inputs: Inputs) -> Element(Msg) {
  let candidates = today.candidates(inputs, item)
  let headline_id = "choose-" <> key.assignment_id <> "-" <> key.workout_id
  html.dialog(
    [
      class("choice-dialog"),
      attribute.attribute("data-open", "true"),
      attribute.attribute("aria-labelledby", headline_id),
      event.on("close", decode.success(CancelClicked)),
    ],
    [
      html.h2([class("dialog-headline"), attribute.id(headline_id)], [
        html.text("Which activity was it?"),
      ]),
      case candidates {
        [] ->
          html.p([class("dialog-supporting")], [
            html.text(
              "You have no activity on "
              <> date.format(item.scheduled.date)
              <> ". Add it in Activities, then link it here.",
            ),
          ])
        _ ->
          html.ul(
            [class("choices")],
            list.map(candidates, fn(row) {
              html.li([], [
                html.button(
                  [
                    attribute.type_("button"),
                    class("choice-row"),
                    event.on_click(PickClicked(key, row.activity.id)),
                  ],
                  [
                    icon.view(icon.DirectionsRun),
                    html.text(describe(row, inputs)),
                  ],
                ),
              ])
            }),
          )
      },
      html.form([attribute.attribute("method", "dialog"), class("actions")], [
        case candidates {
          [] ->
            html.a(
              [
                class("md-button md-button-text"),
                attribute.href(route.to_path(route.Activities)),
              ],
              [html.text("Go to activities")],
            )
          _ -> element.none()
        },
        button.text([attribute.type_("submit")], [html.text("Cancel")]),
      ]),
    ],
  )
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
      units.format_planned_km(d) <> " · " <> units.format_duration(t)
    Some(d), None -> units.format_planned_km(d)
    None, Some(t) -> units.format_duration(t)
    None, None -> ""
  }
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}
