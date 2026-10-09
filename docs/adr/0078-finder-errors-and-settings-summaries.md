# 0078. The person finder's errors at its field, and Settings rows that say what is set

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's other items); agent (the details below)

## Context

- The person finder (Coaches, Sharing; [ADR 0024](0024-coach-grants-screen.md), [0029](0029-sharing-plans.md)) showed
  every problem, from "Enter a complete e-mail address." to being offline, as one paragraph under the form, with the
  field unmarked ([ADR 0059](0059-floating-labels-and-field-errors.md)). Once someone was found, Find and the
  confirming button were both filled.
- The Settings list ([ADR 0049](0049-settings-list-and-banners.md), [0065](0065-settings-single-pane.md)) described
  each section with the same words whatever was set.

## Decision

- The finder tells a problem with the address (none typed, incomplete, your own, nobody with it, already has access)
  from a lookup that could not be made (offline, signed out, too many, the server, an unreadable answer): the first is
  the field's error, which marks it; the second, `Unreachable`, stays under the form. Once someone is found, Find is
  tonal, so the confirming button is the one filled button.
- Settings rows say what is set, from what is on the device: training zones "Max 185 bpm · threshold 4:30 /km" (or
  "Default zones: set yours"), coaches "Bob can see your training", "2 coaches" or "Nobody can see your training", and
  Strava "Connected" once its status is known. Until the data is read they keep their descriptions.

## Consequences

- Settings can be checked at a glance. Strava's status is only known after its page was opened in the session, so
  its row says "Connected" from then on.
