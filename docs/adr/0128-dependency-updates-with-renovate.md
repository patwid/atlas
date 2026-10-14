# 0128. Dependency update pull requests from Renovate

- Status: Accepted
- Date: 2026-10-14
- Deciders: owner (Renovate); agent (the configuration below)

## Context

Nothing updated the project's dependencies so far. They live in five places: `flake.lock` (nixpkgs unstable, which gives CI,
the dev shell and the production server Gleam, Erlang, Node and PocketBase; [0032](0032-nix-flake-dev-shell.md),
[0090](0090-nixos-module.md)), the GitHub Actions in `.github/workflows/`, the Hex packages in `frontend/gleam.toml` and
`manifest.toml`, the npm packages of the browser tests in `frontend/test-js/`, and the toolchain pins in `.tool-versions`
([0006](0006-repository-layout-and-toolchain.md)). CI runs on every pull request ([0042](0042-ci-through-flake-checks.md)), and a
push to `master` deploys to production ([0091](0091-deploy-to-hetzner-with-caddy.md)).

## Options considered

1. **Renovate** (Mend's hosted GitHub App) — covers all five: Nix flake inputs, GitHub Actions, Gleam, npm and `.tool-versions`
   (PocketBase through a regex manager). Grouping, schedules and a dependency dashboard issue.
2. **Dependabot** — built into GitHub, but has no Gleam support and does not update `.tool-versions`; Nix flake support is recent
   and limited.

## Decision

We will use Renovate with `.github/renovate.json5`:

- Pull requests are opened before 6 a.m. on Mondays (Europe/Zurich), at most five open at once, listed in a dependency dashboard
  issue. Commit messages stay plain (no semantic prefixes), like the project's own.
- The Nix manager is enabled; weekly lock file maintenance refreshes `flake.lock`, `manifest.toml` and `package-lock.json`.
- Minor and patch updates are grouped per ecosystem (GitHub Actions, npm, Gleam); majors come one per pull request.
- `.tool-versions`: Gleam through the asdf manager, PocketBase through a regex manager on its GitHub releases. Erlang is left
  out: its major is tied to `beam27Packages` in `flake.nix` and to the apt packages, and is changed by hand.
- Nothing is merged automatically, since merging to `master` deploys.

## Consequences

- The owner has to install the Renovate GitHub App on `patwid/atlas`; it then opens the dashboard issue and the first PRs.
- `.tool-versions` and nixpkgs are updated separately, so the dev shell's version warning may show until both have caught up.
- A `flake.lock` update changes the production system as well; review it with that in mind.
- Renovate's hosted runner needs Nix and Gleam to update `flake.lock` and `manifest.toml`; if a lock file PR fails there, revisit.
