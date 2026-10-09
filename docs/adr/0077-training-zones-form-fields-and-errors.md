# 0077. The training zones form: outlined fields, errors at their input, Save in view

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's other items); agent (the details below)

## Context

The training zones page ([ADR 0034](0034-heart-rate-zone-settings.md)-[0036](0036-pace-zone-settings.md)) has
eighteen inputs. Its zone inputs were plain 40px boxes with a separate small label and no unit, unlike the outlined
fields with floating labels everywhere else ([ADR 0059](0059-floating-labels-and-field-errors.md)). Any problem was
one message above Save, at the bottom of a long page, with no input marked. Long paragraphs explained the defaults,
the buttons "Work out zones from threshold pace" wrapped on a phone, and "Undo changes" appeared and disappeared, and
read like the snackbars' Undo ([ADR 0056](0056-menus-and-undo.md)).

## Decision

- `hr_zones`, `lactate_zones` and `pace_zones` have `parse_at`, which says which input a problem is about (the
  maximum or threshold, a zone's start, or none); `parse` is `parse_at` without it.
- Every zone start is an outlined field ("Zone 3 from") with its unit as suffix (bpm, mmol/L, /km), where it ends
  beside it. A problem shows under its input, which is marked (`aria-invalid`) and gets the focus, so it is in view; a
  problem with no input of its own shows by the buttons.
- The defaults are the maximum's and the threshold's supporting text; the buttons are "Calculate heart rate zones"
  and "Calculate pace zones".
- Save zones and Discard changes (disabled until something changed) stay in view at the bottom of the screen
  (sticky, above the navigation bar).

## Consequences

- The form is longer, each field being 56px high, but Save no longer needs scrolling to.
