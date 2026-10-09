# 0083. The person finder's search as an icon button in its field

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (found the field and Find button on the Sharing tab off); agent (the details below)

## Context

The person finder (Sharing, Coaches; [ADR 0024](0024-coach-grants-screen.md), [0029](0029-sharing-plans.md),
[0078](0078-finder-errors-and-settings-summaries.md)) put a 40px filled pill, Find, beside its 56px outlined field.
The two shapes did not match, Find was the loudest thing on the tab until someone was found, the button's text
changed to "Looking…" and so changed its width, and on a phone the field's long label ("Share with someone by e-mail
address") was cut off in the width left beside the button.

## Options considered

1. **An icon button at the field's end**, as the date and time fields have ([ADR 0054](0054-material-date-and-time-pickers.md)).
   The field keeps the full width; nothing moves while looking.
2. **A button that opens a dialog with the field.** Tidier when there is no one to add, but one more step and a
   larger change.

## Decision

- Find is a search icon button at the field's end, named "Find" for screen readers; Enter still finds. While it looks
  it is disabled and shows a small loading indicator, named "Looking…".
- The label is "E-mail address"; what it is for is the line under it ("Who to share this plan with", "The coach to
  let see your training"), which a problem with the address replaces.
- The confirming button (Share plan, Give access) is the only filled button.
- A field with a button at its end takes the field's top margin on its wrapper, so the button lines up with the input
  in a flex row too.

## Consequences

- The field and its action read as one control at every width, and the tab's emphasis is on who it is shared with.
- A search icon is less explicit than the word Find; the help line and Enter make up for it.
