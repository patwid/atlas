# 0084. Training zones: the Calculate buttons under their field

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to fix the other field with a button beside it); agent (the details below)

## Context

On the training zones form ([ADR 0034](0034-heart-rate-zone-settings.md), [0077](0077-training-zones-form-fields-and-errors.md)),
"Calculate heart rate zones" and "Calculate pace zones" sat beside the maximum heart rate and threshold pace fields,
as Find once sat beside the person finder's field ([ADR 0083](0083-person-finder-search-in-the-field.md)). The long
labels left the field narrow next to two lines of help, and on a phone the button wrapped onto a line of its own at
an odd distance. An icon in the field would not do: the buttons fill in the zones below and need their words.

## Decision

Each field takes the full width, with its tonal Calculate button on the line under its help, at the start.

## Consequences

The field and its help read at every width, and the button sits between what it reads and the zones it fills.
