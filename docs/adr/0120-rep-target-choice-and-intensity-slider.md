# 0120. A rep is run at a zone or at a race goal, chosen first; its intensity is a slider

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked for each rep to be either of the zone or the race goal kind, a zone by default, and for the
  race goal's intensity to be set with a slider); agent (the details below)

## Context

Since [0118](0118-reps-at-a-race-goal-intensity.md) a rep shows a Zone select and, below it, a Rep race goal select with
"No race goal"; choosing one clears the other, and the intensity is typed as a number. Both selects are in view at once,
although a rep is only ever run at one of them.

## Options considered

1. **A segmented choice, Zone or Race goal, then only the fields of that kind; the intensity as a range slider**
   (chosen) — says up front that the two exclude each other, and a slider cannot be given a value outside 1 to 100.
2. **Keep both selects, only replace the intensity field with a slider** — smaller change, but leaves the confusion.

## Decision

Option 1. Nothing changes in what is stored (0118).

- **Rep run at**: each set's rep starts with segmented buttons, **Zone** and **Race goal**, set to Zone for a new rep.
  It is shown, as the goal select was, only when the plan's athlete has goals or the rep has one; otherwise a rep has
  its zone only.
- **Zone**: the rep's Zone select, as before. **Race goal**: the Rep race goal select takes the zone's place, without a
  "No race goal" option, and a **Rep intensity** slider from 1 to 100 % in steps of 1 follows the rep's fields.
- Choosing Race goal takes the first of the athlete's goals at 100 % and clears the zone; choosing Zone clears the goal
  and intensity. A rep's kind is read from whether it has a goal, so the form keeps no state of its own for it.
- Moving the slider works out the rep's distance or time as typing the intensity did (0118).

## Consequences

- Warm-up, cool-down and recoveries keep zones only, as in 0118.
- An intensity is always a whole number from 1 to 100 when set with the slider; the check stays for steps from elsewhere.
