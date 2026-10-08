//// The coach's side: the athletes who gave access, and one athlete's progress (ADR 0031). Read-only
//// views over data the device already holds; there is no state and nothing to change here.

import atlas/activities_page
import atlas/activity_form.{type Row}
import atlas/date
import atlas/grants.{type Person}
import atlas/plan.{type Assignment}
import atlas/progress
import atlas/route
import atlas/today.{type Inputs}
import atlas/ui/empty
import atlas/ui/icon
import atlas/ui/layout
import atlas/units
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// How many weeks the progress table shows.
pub const weeks_shown = 6

/// How many recent activities are listed.
pub const activities_shown = 10

pub fn view_list(athletes: List(Person)) -> Element(msg) {
  html.section([class("athletes")], [
    case athletes {
      [] ->
        empty.view(
          icon.Group,
          "Nobody has given you access yet",
          "An athlete adds you under Settings, Coaches, with your e-mail address.",
          None,
        )
      people ->
        layout.list(
          list.map(people, fn(person) {
            html.li([], [
              html.a([attribute.href(route.to_path(route.Athlete(person.id)))], [
                html.text(person.name),
              ]),
            ])
          }),
        )
    },
  ])
}

/// `athlete` is `None` for someone the user does not coach. `inputs.user_id` must be the athlete.
pub fn view_athlete(athlete: Option(Person), inputs: Inputs) -> Element(msg) {
  case athlete {
    None ->
      html.section([class("athlete")], [
        html.p([class("muted")], [html.text("You do not coach this person.")]),
      ])
    Some(person) -> {
      let weeks = progress.weeks(inputs, weeks_shown)
      html.section([class("athlete")], [
        html.p([class("muted")], [
          html.text(
            "You can see this because "
            <> person.name
            <> " gave you access. It is read-only.",
          ),
        ]),
        summary(weeks),
        weeks_table(weeks),
        following(inputs),
        recent(inputs),
      ])
    }
  }
}

fn summary(weeks: List(progress.Week)) -> Element(msg) {
  case weeks {
    [] -> element.none()
    [current, ..earlier] -> {
      let missed =
        list.fold(earlier, current.missed, fn(total, week) {
          total + week.missed
        })
      html.p([class("summary")], [
        html.text(
          "This week: "
          <> int.to_string(current.done)
          <> " of "
          <> int.to_string(current.planned)
          <> " workouts done. Missed in the last "
          <> int.to_string(weeks_shown)
          <> " weeks: "
          <> int.to_string(missed)
          <> ".",
        ),
      ])
    }
  }
}

fn weeks_table(weeks: List(progress.Week)) -> Element(msg) {
  html.div([class("table-wrap")], [
    html.table([class("progress")], [
      html.caption([], [
        html.text(
          "The last " <> int.to_string(weeks_shown) <> " weeks, newest first",
        ),
      ]),
      html.thead([], [
        html.tr([], [
          header("Week of"),
          header("Planned"),
          header("Done"),
          header("Missed"),
          header("Planned km"),
          header("Trained km"),
        ]),
      ]),
      html.tbody(
        [],
        list.map(weeks, fn(week) {
          html.tr([class("week-row")], [
            html.th([attribute.scope("row")], [
              html.text(date.format(week.start)),
            ]),
            cell("Planned", int.to_string(week.planned)),
            cell("Done", int.to_string(week.done)),
            cell("Missed", case week.missed {
              0 -> "0"
              n -> int.to_string(n)
            }),
            cell("Planned km", km(week.planned_distance_m)),
            cell("Trained km", km(week.activity_distance_m)),
          ])
        }),
      ),
    ]),
  ])
}

fn header(text: String) -> Element(msg) {
  html.th([attribute.scope("col")], [html.text(text)])
}

/// `label` is the column's header, shown next to the value when a phone shows each week as a card (ADR 0051).
fn cell(label: String, text: String) -> Element(msg) {
  html.td([attribute.attribute("data-label", label)], [html.text(text)])
}

/// Whole kilometres with one decimal: `21.0`, `8.5`.
fn km(meters: Float) -> String {
  let tenths = float.round(meters /. 100.0)
  int.to_string(tenths / 10) <> "." <> int.to_string(tenths % 10)
}

fn following(inputs: Inputs) -> Element(msg) {
  let mine =
    list.filter(inputs.assignments, fn(row) {
      row.assignment.athlete_id == inputs.user_id
    })
    |> list.sort(fn(a, b) {
      date.compare(b.assignment.start_date, a.assignment.start_date)
    })
  html.div([class("group")], [
    html.h3([], [html.text("Plans they follow")]),
    case mine {
      [] -> html.p([class("muted")], [html.text("Not following a plan.")])
      rows ->
        layout.list(
          list.map(rows, fn(row) {
            html.li([], [
              html.strong([], [html.text(plan_title(inputs, row.assignment))]),
              html.p([class("muted")], [
                html.text("Starts " <> date.format(row.assignment.start_date)),
              ]),
            ])
          }),
        )
    },
  ])
}

fn plan_title(inputs: Inputs, assignment: Assignment) -> String {
  case list.find(inputs.plans, fn(p) { p.id == assignment.plan_id }) {
    Ok(found) -> found.title
    // A plan the coach cannot read: only its dates are known.
    Error(Nil) -> "A plan you cannot open"
  }
}

fn recent(inputs: Inputs) -> Element(msg) {
  let rows = progress.recent_activities(inputs, activities_shown)
  html.div([class("group")], [
    html.h3([], [html.text("Recent activities")]),
    case rows {
      [] -> html.p([class("muted")], [html.text("No activities yet.")])
      _ -> layout.list(list.map(rows, fn(row) { activity_view(row, inputs) }))
    },
  ])
}

fn activity_view(row: Row, inputs: Inputs) -> Element(msg) {
  let a = row.activity
  let when = case
    date.local_datetime(a.started_at, inputs.offset_at(a.started_at))
  {
    Ok(#(day, hour, minute)) ->
      date.format(day) <> ", " <> pad2(hour) <> ":" <> pad2(minute)
    Error(Nil) -> "Unknown time"
  }
  let figures =
    [
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
  html.li([], [
    html.strong([], [
      html.text(case row.name {
        "" -> activity_form.sport_label(a.sport)
        name -> name
      }),
    ]),
    html.p([class("muted")], [
      html.text(when <> " · " <> activity_form.sport_label(a.sport)),
    ]),
    case figures {
      "" -> element.none()
      text -> html.p([], [html.text(text)])
    },
    activities_page.view_on_strava(row),
  ])
}

fn pad2(n: Int) -> String {
  string.pad_start(int.to_string(n), 2, "0")
}
