# 0028. Copying a plan

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: plans can be shared, and someone who receives one needs a version of their own to change)

## Context

A plan that belongs to someone else (public, shared or assigned) can be read but never changed ([0009](0009-data-model-and-api-rules.md)).
People adapt plans, so they need to make their own version. Conflicted copies ([0020](0020-sync-runner-and-conflicted-copies.md)) already
exist but copy only one record; a plan is a plan record plus its workouts.

## Decision

- **"Copy to my plans"** is on the screen of every plan on the device, the user's own included. It creates a new plan and a copy of each of its
  workouts, all owned by the user.
- **What a copy is**: the title (`Copy of <title>`, cut to the server's limit of 200 characters), the description, *private* visibility whatever the
  source had, and `source_plan` pointing at the original (the field exists since [0009](0009-data-model-and-api-rules.md)). Each workout keeps its day, position,
  title, kind, notes and targets. Assignments are not copied: whoever copies a plan decides when to start it ([0023](0023-assignments.md)).
- **Order matters**: the plan is created first and its workouts after it, one after the other. The outbox sends strictly in order ([0016](0016-sync-core-outbox-and-cursor.md)),
  so the server has the plan before it is asked to attach workouts to it. If the plan were refused, its workouts would be refused too and the
  rejection would be shown, with nothing half-made left on the device.
- **Pure**: `plan_copy.build` decides the records and takes the ID source as a parameter; the app performs it.
- **One copy per click**: the button is replaced by "Copying…", then by "Copied to your plans. Open your copy · Copy again", so a double click
  cannot make two copies. "Copy again" is an explicit choice. The confirmation shows only on the plan that was copied.
- **Nothing is copied before the workouts have been read** from the device database; the screen then says to try again in a moment, because copying
  earlier would produce a plan without its workouts.
- **Reading the source** needs no new permission: a plan is readable together with its workouts ([0009](0009-data-model-and-api-rules.md)).

## Consequences

- A copy is a snapshot. Later changes to the original do not reach it, and the link `source_plan` is for people (and later for "update from original"), not used yet.
- Copying a long plan queues one record per workout, sent one after another; on a slow connection the copy takes a moment to reach the server, while the
  copy is usable on the device at once.
- Workout `steps` (structured intervals) are not copied because they are not edited anywhere yet ([0022](0022-workouts-in-a-plan.md)).
- The whole-app test copies a public plan of someone else, checks the new plan and both workouts on the server (including `source_plan`, private visibility
  and the targets), that the original is untouched, and that the copy can be opened and renamed by its new owner.
