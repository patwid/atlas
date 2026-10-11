# 0110. Every plan is for one athlete; sharing and public plans are gone

- Status: Accepted
- Date: 2026-10-11
- Deciders: owner (a plan is assigned to one person when it is made, oneself by default; the Schedule and Sharing tabs
  go; sharing is dropped entirely; existing plans are split; only the coach removes a plan from an athlete; the
  athlete cannot be changed later, on the agent's recommendation); agent (the details below)

## Context

A plan was a template: anyone it was shared with ([0029](0029-sharing-plans.md)) or, if public, anyone signed in could
start it, and each start was an assignment with its own date ([0023](0023-assignments.md), [0108](0108-plan-start-date.md)).
The plan page had a Schedule tab listing everyone following it and a Sharing tab for its owner
([0058](0058-plan-page-tabs-and-app-bar-actions.md)). In practice a plan is one athlete's season: a coach plans it for
one person, or someone plans their own. The owner asked to drop both tabs and to give each plan one athlete when it is
made, oneself unless someone else is chosen.

## Options considered

For where the athlete is kept:

1. **An `athlete` field on the plan** — the cleanest model, but matches, Home, the coach's view of an athlete and the
   membership sweep all work from assignments, and matches point at them. All of it would change, and matches would
   need a new link.
2. **One assignment per plan, made with it (chosen)** — the assignment stays the record of "this athlete follows this
   plan", so everything that reads assignments keeps working; the server makes it one per plan and unchangeable.

For whether the athlete can be changed later:

1. **Changeable** — matches link the first athlete's activities to the plan's workouts. Moving the plan would take it
   from them while their history still points at it, and the coach's view of their past weeks
   ([0031](0031-coach-view-of-an-athlete.md)) would change after the fact.
2. **Fixed, with copying for reuse (chosen)** — "this worked for Anna, now Ben does it" is a copy for Ben with its own
   date. A wrong choice is fixed by copying the plan for the right person and deleting the wrong one.

## Decision

- **Schema** (migration `1760001000_one_athlete_per_plan.js`):
  - `assignments`: one per plan (a unique index on `plan`). Only the plan's owner creates it (`assigned_by` is them),
    for themselves or an athlete who granted them access ([0024](0024-coach-grants-screen.md)), and it always follows the
    plan's start date (`start_date` empty). No client can change or remove it (`updateRule` null). The plan's owner can
    read it, besides the athlete and the athlete's coaches, so a coach still sees who a plan is for after access is
    taken back.
  - `plans` and their `workouts` are readable by their owner and by the plan's athlete. `plans.visibility` and the
    `plan_shares` collection are removed. Copying a plan is still possible for anyone who can read it
    ([0028](0028-copy-a-plan.md)).
- **Existing data** is split. A plan keeps one live assignment that its owner made (their own first, then one
  following the plan, then the latest start). Each other live assignment moves to a copy of the plan: owned by whoever
  made that assignment, starting on that assignment's date, with `source_plan` pointing at the original, and with all its
  workouts (deleted ones too). The assignment's matches move to the copy's workouts. A plan with no assignment by its
  owner gets one for its owner. A kept assignment with a date of its own gives the plan that date. Soft-deleted
  assignments are removed with their matches, as the purge would have done ([0014](0014-purge-soft-deleted-rows.md)).
  A deleted plan is not split: it keeps one assignment and loses the others.
- **Creating a plan**: the form asks "For", with Myself first and selected, then each athlete who granted access. It
  only shows when the user coaches someone. The plan and its assignment are created together, the plan first, so the
  outbox sends them in that order ([0016](0016-sync-core-outbox-and-cursor.md)).
- **Copying**: a copy is for the user, or for one of their athletes when they coach someone, and is assigned with it.
  A copy of a plan without a date starts on the coming Monday, since its assignment needs a date to follow.
- **The plan page** has no tabs: the description, who the plan is for or from, and the calendar. "Add workout" is its
  main action.
- **The plan list** has three groups: "Your plans" (yours, for you), "Your athletes' plans" (yours, for someone else,
  saying who) and "From your coaches" (someone else's, for you, saying who).
- **Removing**: only the owner removes a plan from its athlete, by deleting the plan. The athlete cannot leave it.

## Consequences

- A plan's schedule is its own date: moving the plan moves its athlete, and there is no second date to keep in sync.
- Reusing a plan always makes a copy. Changes to the original no longer reach anyone else.
- Someone who had started a stranger's public plan now owns a copy of it and can change it.
- App versions from before this change still pull `plan_shares`, which is gone, and may try "Change date" or "Remove"
  on an assignment, which the server refuses. They update when resumed ([0103](0103-update-installed-apps-on-resume.md)).
- The coach's other athletes are not involved: a plan is readable by its athlete and its owner only, as before for
  private plans.
- Supersedes [0029](0029-sharing-plans.md), and the parts of [0009](0009-data-model-and-api-rules.md) (public plans,
  `plan_shares`), [0023](0023-assignments.md) (the Schedule section, starting, changing the date and removing),
  [0058](0058-plan-page-tabs-and-app-bar-actions.md) (the tabs) and [0108](0108-plan-start-date.md) (assignments with dates
  of their own) that say otherwise.
