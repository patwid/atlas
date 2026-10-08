# 0043. Plan phases, a weekly distance goal, week intensity and a calendar view

- Status: Proposed
- Date: 2026-10-08
- Deciders: owner (asked for phases, a weekly distance goal, a per-week intensity and a calendar with a sidebar); agent (the details below)

## Context

A plan's length was implicit: its weeks ran to the last week that had a workout, and a workout was placed by
typing a week number and choosing a day ([0022](0022-workouts-in-a-plan.md)). Coaches think of a season in
periods instead: a base phase, a pre-competition phase and a competition phase, each a few weeks long, with a
target volume per week and harder and easier weeks. The owner asked for:

- three phases per plan, each 4 weeks by default;
- a weekly distance goal for the plan;
- an intensity level per week, set while editing the plan;
- a calendar view like an e-mail client's (Outlook), with a sidebar where the plan-wide and per-week settings are
  shown and edited.

## Options considered

1. **Fields on `plans`** — three week counts, a distance goal, and the week intensities as JSON. One record syncs it all; copying and conflicted copies (0020, 0028) carry it without new code.
   An intensity change and an edit of the title on another device conflict as one record (a conflicted copy of
   the plan), which is rare and visible.
2. **A `plan_weeks` collection** (plan, week, intensity) — finer-grained conflicts, but a new collection with
   rules, sync, purge, membership sweep and copy support, for one small value per week.
3. **A `phase` on each workout** — no notion of a phase's length, and empty weeks would have no phase.

## Decision

We take option 1.

- **Schema** (migration `1760000700_plan_phases.js`): `plans` gets `base_weeks`, `pre_competition_weeks`,
  `competition_weeks` (whole numbers 0-52), `weekly_distance_m` (metres, 0-1 000 000, 0 = no goal) and
  `week_intensity` (JSON: one level per week in week order, `""` for none, so `["", "high"]` makes week 2 hard; a
  list rather than an object keyed by week, because the stdlib's decoder accepts plain objects only from the app's
  own JavaScript realm, and IndexedDB need not hand back objects from it). None is required, so app versions that do not know
  them keep working.
- **Phases**: the plan's weeks are the base weeks, then the pre-competition weeks, then the competition weeks. A new
  plan starts with 4 + 4 + 4. A phase may have 0 weeks, but a plan has at least one week and at most 60 (the
  workout form's limit). A plan with 0 + 0 + 0 (made before this change, or by an older app) has no phases and
  is shown as before: its weeks run to the last workout. Workouts after the last phase week are still shown, as
  weeks "after the competition phase", so shortening a phase never hides a workout.
- **Weekly distance goal**: one number for the whole plan, typed in km. Each week shows its planned distance
  against it.
- **Intensity**: per week, one of low, medium or high, or not set. *(Proposed: the owner may want other levels,
  such as a recovery week.)* It is a label for now; it does not change the goal or the workouts.
- **Calendar**: the plan screen shows the workouts as a calendar: one row per week, seven day columns ("Day 1" to
  "Day 7", because weekdays depend on the start date, 0022), grouped in bands per phase. On a phone the days of a
  week stack. Next to it (below it on a phone) a sidebar shows, from top to bottom: the workout form when adding
  or editing a workout, the selected week (phase, intensity, distance against the goal, time), and the plan's
  settings (phase lengths and goal). The owner edits them there; others see them read-only. A day's "+ Add"
  opens the form for that day; the form keeps a week and a day choice to move a workout, with the weeks named by
  their phase ("Base, week 2").
- **Creating a plan** asks for the phase lengths and the goal along with the title.

## Consequences

- An intensity change writes the plan record; the sync guard (0011) treats it like any other plan edit.
- `plan.length_days` (and so an assignment's end date) still follows the last workout, not the phases. Showing an
  assignment's end as the end of the competition phase is possible later.
- Intensities of weeks beyond the plan's weeks stay stored when a phase is shortened and come back when it grows.
- Open: whether intensity should scale the goal per week, and whether the goal should be settable per week.
