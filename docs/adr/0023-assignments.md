# 0023. Starting plans: assignments

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: following a plan from a start date, and coaches assigning plans, as the owner asked)

## Context

A plan is a template ([0009](0009-data-model-and-api-rules.md)); it becomes a schedule when someone
starts it on a date. The assignment is the record of that: the plan, the athlete, who assigned it and the
first day. The server decides who may create one (the plan must be the creator's own or public, and the
athlete must be the creator or someone who granted them coach access) and who may change one (the athlete
and whoever assigned it). The screens should not offer what the server would refuse.

## Decision

- **Where**: the plan's screen has a Schedule section under its workouts, listing everyone who is following the plan
  and can be seen by the user: when each starts and ends (with weekdays, such as "Starts Mon 2 Nov 2026 · ends Sun 29 Nov 2026"),
  and who assigned it when that is not the athlete.
- **Start**: "Start this plan" asks for the first day (a date picker, today by default; past dates are allowed, and
  years outside 2000-2100 are refused as typing mistakes). The button only appears for plans that are the user's own
  or public, which is what the server accepts, so a private plan shared with the user can be read but not started.
- **Change and remove**: "Change date" and "Remove" appear for the athlete and for whoever assigned it, matching the server's
  update rule. Removing asks again. Only the start date can change (plan, athlete and assigner are fixed, 0009). Removing is
  a soft delete.
- **Athletes**: when the user is a coach for someone, the start form also offers "For: Myself / each athlete who granted access",
  and a submit for anyone else is refused before it is queued. How grants are made and named is in
  [0024](0024-coach-grants-screen.md); until a grant carries names, an athlete is shown as "Unnamed athlete".
- **Same pattern** as the other screens ([0021](0021-plans-screens.md)): own state, writes returned as `Action`s and performed
  by the sync runner, data read from the device database. The pure parts are `assignment_form` and `grants`.

## Consequences

- An athlete sees a plan a coach assigned (the plan and its workouts are readable through the assignment, 0009) and cannot
  start it again on their own if it is private; they can change the date because they are the athlete.
- The schedule only lists assignments of the plan on screen. A list of everything the user follows, by date, is the next screen (Today).
- Ending a plan early is done by removing the assignment; there is no "paused" state.
- The whole-app tests cover starting, re-dating and removing an own plan against a real PocketBase, starting a public plan of
  someone else, and that a private shared plan offers no start.
