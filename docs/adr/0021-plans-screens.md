# 0021. The plans screens

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: the owner asked for creating and sharing plans)

## Context

Plans are the first thing users create. The screens are also the first consumer of the local write API (0020),
the record decoders (0019) and the sync engine (0018), so they set the pattern the other screens will follow.

## Decision

- **Screens**: `/plans` lists the user's plans and, apart, plans shared with them (public ones and ones
  assigned to them), with a form for a new plan. `/plans/<id>` shows one plan with Edit and Delete for its
  owner. Plans of other people are read-only and say so.
- **Pattern for screens**: a module with its own `Model`, `Msg`, `update` and views, embedded in the app with
  `element.map` and `effect.map` (as `syncing` is). `update` never writes data itself: it returns `Action`s
  (`Create`, `Edit`, `Delete`) that the app performs through the sync runner. Validation and the choice of
  fields to write are pure and tested apart (`plan_form`).
- **Reading**: the screen reads its collection from the device database and reads it again whenever the
  runner reports that records changed (a revision counter). A write by the user, a pull, an acknowledged
  save and a conflict all take the same path, so the screen cannot show something the device does not hold.
  There is no separate optimistic state: the write reaches IndexedDB within milliseconds.
- **Writes**: a new plan carries its owner, title, description and visibility. An edit sends only the fields the
  user changed, with the local copy's `updated` as base (0011); an edit that changes nothing writes nothing.
  Deleting asks once more ("Delete this plan?") and is a soft delete (0009).
- **Validation** repeats the server's limits (title 1-200 characters, description up to 5000) before anything is queued.
- **Honesty about sync**: a plan that has not reached the server yet is marked "Not synced yet".
- **Plain styling and accessibility**: labelled fields, `role="alert"` for errors and the delete question,
  keyboard-operable buttons, and the first field focused when a form opens.

## Consequences

- Reading a whole collection on every change is fine for hundreds of plans. A query layer or secondary
  indexes would be needed for thousands.
- Sharing with named users (`plan_shares`), assigning to athletes and the workouts of a plan have no screens yet.
  The form already has the visibility choice (private or public).
- The whole-app tests (`frontend/test-js/app.e2e.test.mjs`) drive these screens in jsdom against a real
  PocketBase: creating (including the empty-title error), editing (only changed fields), deleting with
  the question, a shared plan shown read-only, and a plan pulled in while the app is open.
