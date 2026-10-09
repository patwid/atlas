# 0076. A long plan description is cut to three lines, with More

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's other items); agent (the details below)

## Context

A plan's page shows its description in full above the tabs ([ADR 0058](0058-plan-page-tabs-and-app-bar-actions.md)),
line breaks kept. A description of a few paragraphs, which plans often have, pushed the calendar below the first
screen on a phone.

## Decision

A description longer than three lines or 240 characters shows its first three lines (CSS line clamp) with a More
text button under it, which shows the rest and becomes Less (`aria-expanded`, `aria-controls`). Shorter ones show as
before. Whether it is open is kept in the plans page's model.

## Consequences

- The tabs, and the calendar, start near the top on a phone. Opening one plan's description leaves the next plan's
  open too, until Less.
