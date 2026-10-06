# 0006. Monorepo layout and pinned toolchain

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent

## Context

Atlas has a Gleam/Lustre frontend ([0003](0003-use-gleam-lustre-frontend.md)) and a PocketBase
backend ([0002](0002-use-pocketbase-as-backend.md)), and both change together: the schema, the
API rules and the sync code. PocketBase is pre-1.0 and Gleam releases often, so builds are only
reproducible if every tool is pinned to an exact version.

## Options considered

1. **One repository with `frontend/` and `backend/` (chosen)**: one commit can change the
   schema and the client together, and ADRs live next to both.
2. **Separate repositories**: every cross-cutting change has to be coordinated across repos,
   which adds overhead and no benefit at this size.
3. **Dev container / Nix for the toolchain**: fully reproducible, but heavier than a project
   with three tools needs. Worth revisiting when CI is added.

## Decision

- Layout:
  - `frontend/`: Gleam project (`atlas`, JavaScript target)
  - `backend/`: `pb_hooks/`, `pb_migrations/` and `pb_public/`, the latter filled by the frontend build.
    `pb_data/` is git-ignored.
  - `docs/adr/`, `scripts/`
- Tool versions are pinned in `.tool-versions` (asdf-compatible): Gleam 1.19.0, Erlang/OTP 27
  (Ubuntu package, used only by Gleam tooling and tests on the Erlang target), and PocketBase 0.40.4.
- `scripts/install-tools.sh` installs exactly those versions into `~/.local/bin`.
- Upgrading a tool means bumping `.tool-versions`, adding a CHANGELOG entry and, for PocketBase
  minor versions, reading its release notes.

## Consequences

- One `git clone` plus `scripts/install-tools.sh` gives a working environment on Debian/Ubuntu.
- Erlang comes from the distro, so only the major version is pinned. That is enough because
  the app does not run on BEAM.
