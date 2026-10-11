# 0108. A plan has a start date; its calendar shows real days from a Monday

- Status: Accepted. Assignments with dates of their own are gone: [0110](0110-one-athlete-per-plan.md).
- Date: 2026-10-11
- Deciders: owner (a start date set when a plan is made and changeable later, days and weeks with dates, assignments
  driven by the plan's date, a calendar anchored on Mondays with days outside the plan dimmed and read-only); agent
  (anchoring on the start date rather than a race date, the details below)

## Context

A plan was a template without dates ([0009](0009-data-model-and-api-rules.md)): a workout sat on `day_index` (0 = the
plan's first day), and only an assignment gave the plan a start date ([0023](0023-assignments.md)). So the plan's
calendar said "Week 3, Day 2" rather than "Wed 18 Nov", and a coach planning a season could not see which weekday a
workout fell on. The owner asked for a start date given when a plan is made, changeable later, with each day and week
on a real date, and for the plan's date to drive the assignment. The calendar should start its weeks on Monday; days
of those weeks that fall outside the plan are dimmed and read-only.

## Options considered

1. **A date on each workout** — the calendar needs no arithmetic, but moving the plan rewrites every workout (many
   edits through the outbox, conflicts, a half-moved plan on a device that synced only some), and copying a plan has
   to shift every date.
2. **A start date on the plan; workouts keep a day number (chosen)** — moving the plan is one field on one record;
   dates are worked out.
3. **A race date on the plan, the start worked out backwards from the phases** — how coaches often think, but the
   owner asked for a start date, and lengthening the base phase would move the start rather than the race. A race date
   can be added later as a marker without changing this model.

And for what `day_index` counts from:

- **From the start date** (as before): moving the start from a Wednesday to a Monday would turn every Sunday long run
  into a Friday one.
- **From the Monday of the plan's first week (chosen)**: moving the start keeps every workout on its weekday; moving it
  into another week moves the whole plan by whole weeks.

## Decision

- **Schema** (migration `1760000900_plan_start_date.js`): `plans.start_date` (`YYYY-MM-DD`, empty for none). Once set
  it cannot be emptied (the update rule refuses it), since assignments may follow it. `assignments.start_date` may now
  be empty: the assignment **follows its plan's start date**. The create and update rules accept an empty one only when
  the plan has a date.
- **Days**: `day_index` 0 is the Monday of the week the plan starts in. Week 1 is that Monday-to-Sunday week, so a plan
  starting on a Wednesday has a first week of five days. Phases count these calendar weeks
  ([0043](0043-plan-phases-goal-and-calendar.md)).
- **The plan's days**: from the start date to the Sunday of its last phase week, or of the last week with a workout.
  Days of week 1 before the start are dimmed and read-only: they have no add button, and the workout form refuses
  them. A workout that is there (because the start was moved later in its week) is still shown, dimmed, so the owner
  can move or delete it. It is on nobody's schedule.
- **The calendar** names its columns Mon to Sun, and a dated plan shows each day's date and each week's dates
  ("Week 3 · 16–22 Nov"). A plan without a date (made before this change and never started) shows weekdays only.
- **Creating a plan** asks for the start date, the coming Monday by default. Edit can change it, but cannot empty it.
  An undated plan can stay undated when edited.
- **Assignments**: starting one's own plan, for oneself or as a coach for an athlete, makes an assignment that follows
  the plan, so moving the plan moves them. Whoever starts someone else's plan (public or shared) picks their own date,
  by default the plan's while it is still ahead, else the coming Monday, so the owner moving their plan does not move
  strangers. An own date works like the plan's:
  workouts keep their weekday from that week's Monday, and the days before the date are left out. "Change date" on
  a following assignment gives it its own date. The owner moves their own following assignments by changing the
  plan's date.
- **Existing data keeps its dates**: the migration gives every plan with an assignment the start date of one of them
  (the owner's own, else one the owner made, else any; the latest), moves the plan's workouts by that day's weekday,
  and makes the owner's assignments on that date follow the plan. An assignment on another weekday of the same plan
  keeps its own date, but its workouts move by up to three days to keep their weekday.
- **Copying** a plan copies its start date ([0028](0028-copy-a-plan.md)); the copy's owner can change it.

## Consequences

- One plan edit moves a whole schedule. The sync guard ([0011](0011-sync-conflict-guard.md)) treats it like any plan edit.
- An assignment's end is the end of the plan's days. With phases that is now the Sunday of the last phase week rather
  than the last workout, which answers the open point in 0043.
- App versions from before this change cannot read an assignment without a date, so they leave out following
  assignments until they update, which they do when resumed ([0103](0103-update-installed-apps-on-resume.md)). They
  would also read `day_index` from the start date rather than its Monday.
- Supersedes the part of [0009](0009-data-model-and-api-rules.md) and [0023](0023-assignments.md) that says a plan has
  no dates and every assignment has its own.
