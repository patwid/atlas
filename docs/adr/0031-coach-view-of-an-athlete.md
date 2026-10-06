# 0031. The coach's view of an athlete's progress

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: coaches can see their athletes' progress, as the owner asked)

## Context

A coach can read an athlete's assignments, activities and stored matches once the athlete has granted access
([0009](0009-data-model-and-api-rules.md), [0024](0024-coach-grants-screen.md)), and those records sync to the coach's device like any others.
What was missing was a screen. The athlete's own Today screen already works out, from the same records, what was asked for and what was
done ([0026](0026-today-screen.md)), so the coach should see the same picture.

## Decision

- **Athletes** (`/athletes`, with its own tab shown only to someone who has athletes; also linked from Settings): the people who gave the user access,
  each linking to `/athletes/<id>`. Someone who is not the user's athlete gets "You do not coach this person.", and nothing else.
- **An athlete's page** is read-only and has no buttons:
  - **The last six weeks, newest first, as a table** (weeks start on Monday): workouts planned, done and missed, planned distance, and the total
    distance the athlete trained (all activities, whether or not they belong to a workout).
  - **A summary** for this week and the missed workouts of the six weeks.
  - **The plans they follow**, with start dates. A plan the coach cannot read shows as "A plan you cannot open" with its dates.
  - **Their ten latest activities**, Strava ones included (the owner decided coaches may see them, [0005](0005-wearable-data-integration.md)).
- **No new data and no new rules.** The figures come from the same pure code as Today (`today`), run for the athlete (`items_between` for any range),
  rolled up by `progress`. What a coach sees is what the athlete sees, including suggested matches the athlete has not confirmed yet.
  Everything is on the device, so it also works offline.
- **Dates** use the UTC offset that applied at each activity ([0015](0015-domain-core.md) addendum), so a run just after midnight counts in the right week.
- **Access removal reaches the page**: the sweep ([0030](0030-membership-sweep.md)) takes the grant and the athlete's data from the coach's device,
  after which the tab disappears and the page says the user does not coach this person. A test shows it.

## Consequences

- A plan the coach cannot read (made by another coach, say) gives dates but no workout titles, and its workouts do not appear in the planned and done
  counts because the coach's device does not have them. Readable plans, which include every plan the coach assigned, count fully.
- "Done" includes suggestions the athlete has not confirmed, so the coach may see a workout as done that the athlete would still mark. This is the
  same as the athlete's own screen, and the two stay consistent because they share the code.
- There is no way yet to comment on or adjust the athlete's plan from this screen; changing a plan is done on the plan itself (the coach's own plans) and
  assignments can be changed from the plan's schedule ([0023](0023-assignments.md)).
- Only six weeks are shown. Longer history, charts and comparisons would need their own design.
- The whole-app test builds a plan, an assignment by the coach and an activity by the athlete, checks the totals (3 planned, 1 done, 1 missed, 23 km
  planned, 8 km trained) across five time zones, and then removes the coach's access.
