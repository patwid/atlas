# 0063. One background for all phase bands

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner

## Context

[ADR 0045](0045-material-baseline-colors.md) gave the plan calendar's phase bands three surface containers, from
light to dark: `surface-container-low` (base), `-high` (pre-competition) and `-highest` (competition). The owner wants
all three as light as the base phase.

## Decision

All phase bands use `surface-container-low`. The band titles ("Base phase · 4 weeks", …) name the phases.

## Consequences

- The calendar is calmer; phases are told apart by their titles, not their shade.
