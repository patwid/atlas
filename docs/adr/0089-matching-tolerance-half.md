# 0089. Matching accepts half to one and a half times the plan

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (chose 0.5); agent (the details below)

## Context

[ADR 0015](0015-domain-core.md) left the matching tolerance `Proposed`: an activity could be suggested for a workout when its
distance (or, without a distance target, its moving time) differed from the plan by at most 100 %, so anything from nothing
up to double the planned size. A 1 km jog was then suggested for a 12 km long run, and Home showed the workout as "Looks done".

## Options considered

1. **Keep 1.0** — rarely misses a real match, but suggests clearly wrong ones.
2. **0.5** — fewer wrong suggestions; a run cut to less than half the plan, or more than half again longer, is not suggested.

## Decision

`max_relative_difference` in `matching.gleam` is 0.5: an activity matches when it is between 50 % and 150 % of the planned
distance (or duration). Everything else in 0015 stays: workouts without a target still match any fitting activity of the day,
and existing and manual matches are never changed.

## Consequences

- A run much shorter or longer than planned shows as missed (or to do) until the user links it by hand with "Link activity",
  which is not limited by the tolerance.
- Stored matches are not touched; only new suggestions follow the new rule.
