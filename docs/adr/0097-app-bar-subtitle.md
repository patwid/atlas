# 0097. A subtitle in a plan's medium app bar

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked for the M3 Expressive items left out by ADR 0095); agent (the details)

## Context

M3 Expressive's medium flexible app bar can show a subtitle under the title. A plan's page has the medium app bar
([ADR 0062](0062-material-review-remaining-items.md)), with the plan's name in it. Its length and weekly goal were in
a long line in the page ("10 weeks: 4 base, 4 pre-competition, 2 competition · 40 km a week"), under the chips.

## Options considered

1. **No subtitle.** Nothing changes.
2. **The whole summary as the subtitle.** It is too long for a phone's app bar and would wrap.
3. **The plan's length and goal as the subtitle, the phase split in the page (chosen).** "10 weeks · 40 km a
   week" is the plan at a glance, next to its name. The page keeps "4 base, 4 pre-competition and 2 competition
   weeks".

## Decision

- `shell.Frame` gets a `subtitle`, shown in the medium app bar under the title (`p.bar-subtitle`) in body-large,
  on-surface-variant. A plan's page passes `plans_page.subtitle`, and `plans_page.summary` keeps only the phase split.
- When the page scrolls and the bar becomes the small one, the subtitle is hidden, so the small bar stays one line.
- An athlete's page has no subtitle. The only candidate is "read-only", which the page already says.

## Consequences

- A plan's total weeks and goal are seen without scrolling, and the page's summary line is shorter.
- Other pages can pass a subtitle when they get the medium app bar.
