//// An athlete's progress week by week: what the plan asked for, what was done, what was missed, and how much
//// they trained in total (ADR 0031). Pure. It uses the same schedule and matching as the athlete's own Home screen,
//// with `inputs.user_id` set to the athlete, so the coach sees what the athlete sees.

import atlas/activity_form
import atlas/date.{type Date}
import atlas/plan
import atlas/today.{type Inputs}
import gleam/list
import gleam/option
import gleam/order
import gleam/string

pub type Week {
  Week(
    /// The Monday of the week.
    start: Date,
    /// Workouts asked for (rest days do not count).
    planned: Int,
    /// Of those, linked to an activity (confirmed or suggested).
    done: Int,
    /// Of those, in the past and not done.
    missed: Int,
    planned_distance_m: Float,
    /// Everything the athlete recorded in the week, whether or not it belongs to a workout.
    activity_distance_m: Float,
    activity_count: Int,
  )
}

/// The current week and the `count - 1` before it, newest first. Weeks start on Monday.
pub fn weeks(inputs: Inputs, count: Int) -> List(Week) {
  let this_week = date.start_of_week(inputs.today)
  let first = date.add_days(this_week, -7 * { count - 1 })
  let items = today.items_between(inputs, first, date.add_days(this_week, 6))
  let activities =
    list.filter(inputs.activities, fn(row) { row.owner_id == inputs.user_id })
  offsets(count)
  |> list.map(fn(offset) {
    let start = date.add_days(this_week, -7 * offset)
    week(start, items, activities, inputs)
  })
}

fn week(
  start: Date,
  items: List(today.Item),
  activities: List(activity_form.Row),
  inputs: Inputs,
) -> Week {
  let in_week = fn(day: Date) { date.start_of_week(day) == start }
  let asked =
    list.filter(items, fn(item) {
      in_week(item.scheduled.date) && item.scheduled.workout.kind != plan.Rest
    })
  let recorded =
    list.filter(activities, fn(row) {
      case
        date.local_date(
          row.activity.started_at,
          inputs.offset_at(row.activity.started_at),
        )
      {
        Ok(day) -> in_week(day)
        Error(Nil) -> False
      }
    })
  Week(
    start: start,
    planned: list.length(asked),
    done: count(asked, fn(status) {
      case status {
        today.Done(_, _) -> True
        _ -> False
      }
    }),
    missed: count(asked, fn(status) { status == today.Missed }),
    planned_distance_m: list.fold(asked, 0.0, fn(total, item) {
      total +. option.unwrap(item.scheduled.workout.distance_m, 0.0)
    }),
    activity_distance_m: list.fold(recorded, 0.0, fn(total, row) {
      total +. row.activity.distance_m
    }),
    activity_count: list.length(recorded),
  )
}

fn count(items: List(today.Item), wanted: fn(today.Status) -> Bool) -> Int {
  list.length(list.filter(items, fn(item) { wanted(item.status) }))
}

/// The athlete's most recent activities, newest first.
pub fn recent_activities(
  inputs: Inputs,
  limit: Int,
) -> List(activity_form.Row) {
  inputs.activities
  |> list.filter(fn(row) { row.owner_id == inputs.user_id })
  |> list.sort(fn(a, b) {
    order.lazy_break_tie(
      string.compare(b.activity.started_at, a.activity.started_at),
      fn() { string.compare(a.activity.id, b.activity.id) },
    )
  })
  |> list.take(limit)
}

/// 0, 1, ... count - 1.
fn offsets(count: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, count), fn(_, index) { index })
}
