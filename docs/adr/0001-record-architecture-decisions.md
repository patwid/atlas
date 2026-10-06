# 0001. Record architecture decisions as ADRs, maintained by the agent

- Status: Accepted
- Date: 2026-10-06
- Deciders: project owner (requirement), agent

## Context

Atlas is developed mostly by a coding agent. The project owner wants the agent to record
its decisions and changes itself, without being prompted, so the reasoning behind the
codebase can still be followed later.

## Options considered

1. **Nygard-style ADRs in `docs/adr/`**: one short Markdown file per decision, kept in the repo
   next to the code. Simple and widely recognised.
2. **MADR**: more structured, but its extra sections add little at this project size.
3. **A wiki or external tool**: kept separate from the code, so it falls out of date and the
   agent cannot easily keep it current.

## Decision

We will use lightweight ADRs (Nygard format plus an "Options considered" section) in
`docs/adr/`. The rules are in `AGENTS.md`, which the agent loads in every session:

- Every significant decision gets an ADR, written in the same change that puts it into effect:
  technology or library choices, data model, API or sync contracts, security, external
  integrations, and deviations from an earlier ADR.
- ADRs are numbered in sequence (`NNNN-kebab-title.md`) and listed in `docs/adr/README.md`.
- An accepted ADR is never rewritten. To change a decision, add a new ADR and mark the old
  one `Superseded by NNNN`.
- Decisions that need input from the project owner (cost, legal, product scope) are recorded
  as `Proposed`, and the agent continues on the proposed path.
- User-visible and structural changes are also recorded in `CHANGELOG.md`.

## Consequences

- Every decision leaves a written record without the owner having to ask for one.
- A little overhead on every significant change. Trivial changes (renames, bug fixes that
  don't change the design) do not need an ADR.
- The owner can review `Proposed` ADRs on their own schedule instead of being interrupted.
