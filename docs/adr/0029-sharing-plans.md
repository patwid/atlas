# 0029. Sharing a plan with named people

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: plans can be shared; the rule change was proposed to the owner with the order of work and went ahead)

## Context

A plan can be public (everyone signed in) or shared with named users through `plan_shares` ([0009](0009-data-model-and-api-rules.md)); the server side
has existed since the data model, but there was no screen and no way to look a person up other than for coach access
([0010](0010-user-lookup-by-email.md), [0024](0024-coach-grants-screen.md)). Two things were missing for sharing to be useful:

1. A recipient could read a private plan shared with them but could not *follow* it: starting a plan required it to be the starter's own or public.
2. Screens could not say who a plan is shared with or by, offline, because `users` is not synced.

## Decision

- **Rule change** (migration `1760000300_plan_share_names_and_start_rule.js`): an assignment can also be created for a plan that is **shared with the creator**
  (an undeleted `plan_shares` row for them), next to "own" and "public". It applies to starting a plan for oneself and, as a coach, for an athlete who granted
  access ([0023](0023-assignments.md)). A removed share ends it for new assignments; assignments already made stay.
- **Names ride on the share**, as on coach grants ([0024](0024-coach-grants-screen.md)): `user_name` (the person it is shared with) and `shared_by_name` (the owner).
  They are labels for screens; access is decided by the user IDs. The owner writes both when sharing.
- **Sharing screen** (on the plan's screen, for its owner): who the plan is shared with, each with "Stop sharing" (asks first), and an add form that finds a person by
  e-mail and confirms before sharing. It is the same find-and-confirm flow as adding a coach, from one shared piece of code (`person_finder`).
- **Sharing again** after "Stop sharing" reuses the old row (it is made live again): a person has at most one share row per plan, and a removed row keeps its place.
- **Recipients** see the plan under "Shared with you", with who shared it, read-only; they can copy it ([0028](0028-copy-a-plan.md)) or, now, start it.
- **Only the owner shares.** The server enforces it (`plan.owner`); the screen shows the sharing section to the owner only.

## Consequences

- Sharing is read access. A recipient who wants to change the plan copies it; they never see the owner's other plans.
- Stopping a share hides the plan from the recipient at their next sync but cannot take back what they have already seen or copied
  (as with coach access, [0024](0024-coach-grants-screen.md)). The privacy notice must say so.
- A share to someone who is also a coach of the owner, or to several people, is just several rows; nothing groups them.
- Assignments of a plan whose share was later removed keep working for the athlete: they can still read the plan through their assignment ([0009](0009-data-model-and-api-rules.md)).
