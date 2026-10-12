# 0115. Keep race goals as rows of their own, set in Settings

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked for it), agent

## Context

An athlete wants to write down the races they train for: any number of goals, each with a distance and the time
they want to run it in, both required. They belong to the athlete, not to a plan, so they go in Settings, next to
the training zones. Like everything else they must work offline and sync (ADR 0004), and a coach may see them, as
they see the zones (ADR 0034).

## Options considered

1. **A `goals` collection, one row per goal** — owned by the athlete, synced like the other collections, with
   client-generated IDs. Adding, editing and deleting a goal are ordinary creates, updates and soft deletes, so
   two devices editing different goals never conflict. Costs a migration and one more synced collection.
2. **A JSON list on `athlete_settings`** — no new collection, but every change rewrites the whole list, so edits
   to two goals (or to a goal and the zones) on two devices conflict, and the server cannot check the values.
3. **Goals on a plan** — a plan has a weekly distance goal already (ADR 0043), but a race goal outlives a plan and
   an athlete may have several without a plan.

## Decision

We will add a `goals` collection (option 1): `owner`, `distance_m` (more than 0, up to 1000 km) and `time_s` (a
whole number of seconds, more than 0, up to 48 hours), both required, plus the usual `deleted`, `created` and
`updated`. The owner reads and writes their goals; a coach with access reads them while they are not deleted; nobody
removes rows but the purge job (ADR 0014). Updates go through the `base_updated` guard (ADR 0011).

In the app, Settings gets a Goals page (`/settings/goals`) listing the athlete's goals, shortest distance first,
each with its time and the pace it takes. Add goal is the page's main action (ADR 0068); a goal is added and edited
in a form dialog (ADR 0057) and deleted from it with Undo (ADR 0056, 0080). The distance is typed in kilometres and
the time like the app's other durations: `h:mm:ss`, `h:mm` or minutes. The Settings row says how many goals there are,
or the one goal.

## Consequences

- Goals are only recorded and shown so far: nothing yet compares them with plans or activities, and coaches cannot
  see them in the app yet, although the API lets them.
- A goal has no name or date; either can be added later as optional fields without breaking older apps.
- `1:30` means an hour and a half, as elsewhere in the app, so a 5 km goal of 19:30 is typed `0:19:30`; the help text
  says so.
