//// What the user should do and has done around today: the workouts of the plans they follow, each with a
//// status. Pure. It joins the schedule, the activities and the matches (ADR 0015, 0026).
////
//// A workout is done when the user linked an activity to it (a stored match) or, failing that, when the
//// matching rules propose one. Proposals are never stored by themselves: they are recomputed every time, so
//// they follow the data, and a coach can compute the same view from what they can read.

import atlas/activity_form
import atlas/assignment_form
import atlas/date.{type Date}
import atlas/matching.{type Match, type Stored}
import atlas/plan.{type Plan, type Scheduled, type Workout}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

/// How many days before and after today are shown.
pub const window_days = 7

pub type Status {
  Planned
  Missed
  RestDay
  /// Done with this activity. `confirmed` is true for a link the user made or confirmed (a stored match),
  /// false for one the matching rules suggest.
  Done(activity_id: String, confirmed: Bool)
}

pub type Item {
  Item(
    scheduled: Scheduled,
    plan_title: String,
    status: Status,
    /// The stored match behind the status, when there is one: it can be removed or changed.
    stored: Option(Stored),
  )
}

pub type Inputs {
  Inputs(
    user_id: String,
    today: Date,
    assignments: List(assignment_form.Row),
    workouts: List(Workout),
    plans: List(Plan),
    activities: List(activity_form.Row),
    matches: List(Stored),
    /// The UTC offset in minutes at a UTC timestamp.
    offset_at: fn(String) -> Int,
  )
}

pub type Sections {
  Sections(today: List(Item), upcoming: List(Item), recent: List(Item))
}

/// The workouts around today with their status, ordered by day, then plan and position.
pub fn items(inputs: Inputs) -> List(Item) {
  items_between(
    inputs,
    date.add_days(inputs.today, -window_days),
    date.add_days(inputs.today, window_days),
  )
}

/// The same for any range of days, both ends included. Progress over several weeks uses it (ADR 0031);
/// `inputs.user_id` is the person whose schedule and activities are looked at, not necessarily the signed-in user.
pub fn items_between(inputs: Inputs, from: Date, to: Date) -> List(Item) {
  let mine =
    list.filter(inputs.assignments, fn(row) {
      row.assignment.athlete_id == inputs.user_id
    })
  let every_scheduled =
    list.flat_map(mine, fn(row) {
      plan.schedule(row.assignment, inputs.workouts)
    })
  let near =
    list.filter(every_scheduled, fn(s) {
      date.compare(s.date, from) != order.Lt
      && date.compare(s.date, to) != order.Gt
    })
  let my_activities =
    list.filter(inputs.activities, fn(row) { row.owner_id == inputs.user_id })
  let stored = usable_matches(inputs, every_scheduled, my_activities)
  let proposed =
    matching.propose(
      near,
      list.map(my_activities, fn(row) { row.activity }),
      list.map(stored, fn(s) { s.match }),
      inputs.offset_at,
    )
  near
  |> list.map(fn(s) {
    let stored_here = find_stored(stored, s)
    Item(
      scheduled: s,
      plan_title: title_of(inputs.plans, s.workout.plan_id),
      status: status_of(s, stored_here, proposed, inputs.today),
      stored: stored_here,
    )
  })
  |> list.sort(fn(a, b) {
    date.compare(a.scheduled.date, b.scheduled.date)
    |> order.lazy_break_tie(fn() { string.compare(a.plan_title, b.plan_title) })
    |> order.lazy_break_tie(fn() {
      int.compare(a.scheduled.workout.position, b.scheduled.workout.position)
    })
    |> order.lazy_break_tie(fn() {
      string.compare(a.scheduled.workout.id, b.scheduled.workout.id)
    })
  })
}

/// Today first, then what is coming (soonest first), then what has passed (latest first).
pub fn sections(items: List(Item), today: Date) -> Sections {
  Sections(
    today: list.filter(items, fn(i) { i.scheduled.date == today }),
    upcoming: list.filter(items, fn(i) {
      date.compare(i.scheduled.date, today) == order.Gt
    }),
    recent: list.filter(items, fn(i) {
      date.compare(i.scheduled.date, today) == order.Lt
    })
      |> list.reverse,
  )
}

/// The activities the user can link to an item by hand: their own on the same local day, not used by
/// another stored match, with fitting sports first.
pub fn candidates(inputs: Inputs, item: Item) -> List(activity_form.Row) {
  let taken =
    inputs.matches
    |> list.filter(fn(s) {
      !s.deleted
      && !{
        s.match.workout_id == item.scheduled.workout.id
        && s.match.assignment_id == item.scheduled.assignment_id
      }
    })
    |> list.map(fn(s) { s.match.activity_id })
  inputs.activities
  |> list.filter(fn(row) {
    row.owner_id == inputs.user_id
    && !list.contains(taken, row.activity.id)
    && local_day(row, inputs.offset_at) == Ok(item.scheduled.date)
  })
  |> list.sort(fn(a, b) {
    let fits = fn(row: activity_form.Row) {
      matching.compatible(item.scheduled.workout.kind, row.activity.sport)
    }
    case fits(a), fits(b) {
      True, False -> order.Lt
      False, True -> order.Gt
      _, _ ->
        order.lazy_break_tie(
          string.compare(a.activity.started_at, b.activity.started_at),
          fn() { string.compare(a.activity.id, b.activity.id) },
        )
    }
  })
}

/// The stored row for an activity, removed or not: linking it again reuses the row.
pub fn row_for_activity(
  matches: List(Stored),
  activity_id: String,
) -> Option(Stored) {
  case list.find(matches, fn(s) { s.match.activity_id == activity_id }) {
    Ok(found) -> Some(found)
    Error(Nil) -> None
  }
}

// INTERNALS ---------------------------------------------------------------------------------------

/// Stored matches that still point at something: not removed, the user's own, an activity and a
/// scheduled workout that exist. One per activity and one per workout, the newest row winning.
fn usable_matches(
  inputs: Inputs,
  scheduled: List(Scheduled),
  activities: List(activity_form.Row),
) -> List(Stored) {
  inputs.matches
  |> list.filter(fn(s) {
    !s.deleted
    && s.owner_id == inputs.user_id
    && list.any(activities, fn(a) { a.activity.id == s.match.activity_id })
    && list.any(scheduled, fn(sc) { is_for(s.match, sc) })
  })
  |> list.sort(fn(a, b) { string.compare(b.updated, a.updated) })
  |> list.fold([], fn(kept: List(Stored), s: Stored) {
    case
      list.any(kept, fn(k: Stored) {
        k.match.activity_id == s.match.activity_id
        || {
          k.match.workout_id == s.match.workout_id
          && k.match.assignment_id == s.match.assignment_id
        }
      })
    {
      True -> kept
      False -> [s, ..kept]
    }
  })
}

fn is_for(match: Match, scheduled: Scheduled) -> Bool {
  match.workout_id == scheduled.workout.id
  && match.assignment_id == scheduled.assignment_id
}

fn find_stored(stored: List(Stored), scheduled: Scheduled) -> Option(Stored) {
  case list.find(stored, fn(s) { is_for(s.match, scheduled) }) {
    Ok(found) -> Some(found)
    Error(Nil) -> None
  }
}

fn status_of(
  scheduled: Scheduled,
  stored: Option(Stored),
  proposed: List(Match),
  today: Date,
) -> Status {
  case scheduled.workout.kind == plan.Rest, stored {
    True, _ -> RestDay
    False, Some(s) -> Done(s.match.activity_id, True)
    False, None ->
      case list.find(proposed, fn(m) { is_for(m, scheduled) }) {
        Ok(m) -> Done(m.activity_id, False)
        Error(Nil) ->
          case date.compare(scheduled.date, today) {
            order.Lt -> Missed
            _ -> Planned
          }
      }
  }
}

fn title_of(plans: List(Plan), plan_id: String) -> String {
  case list.find(plans, fn(p) { p.id == plan_id }) {
    Ok(found) -> found.title
    Error(Nil) -> "Plan"
  }
}

fn local_day(
  row: activity_form.Row,
  offset_at: fn(String) -> Int,
) -> Result(Date, Nil) {
  date.local_date(row.activity.started_at, offset_at(row.activity.started_at))
}
