# 0032. Provide the development tools through a Nix flake

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner (asked for a `flake.nix` on nixpkgs unstable, run with `nix develop`)

## Context

The toolchain was installed by `scripts/install-tools.sh` ([0006](0006-toolchain-and-install.md)) from apt and GitHub releases. The owner uses
Nix and wants one command that provides every tool from nixpkgs. The first request was the 26.05 stable channel; it ships gleam 1.18.1 and
PocketBase 0.38.0, further from the pinned versions than unstable does, so the owner switched to `nixos-unstable`.

## Decision

- `flake.nix` defines `devShells.default` on `nixos-unstable`; `flake.lock` pins the revision. Tools: gleam, erlang_27 with `beam27Packages.rebar3`
  (plain `rebar3` would run on OTP 28), pocketbase, nodejs_22, bun, and git, curl, unzip and the usual shell utilities.
- Versions come from nixpkgs, not from `.tool-versions`. On entering the shell a hook warns when gleam or pocketbase differ from the pins.
- `.tool-versions` and `scripts/install-tools.sh` stay for people who do not use Nix.
- The sandbox kit allows `cache.nixos.org` ([0007](0007-sandbox-network-kit.md)).

## Consequences

- Checked on 2026-10-06 with gleam 1.19.0, PocketBase 0.39.11, OTP 27 and Node 22.23: 548 Gleam tests, 66 backend tests and 37 browser-side tests pass.
  The only mismatch is PocketBase (0.39.11, pinned 0.40.4); the warning says so, and nothing in the tests needed 0.40.
- Moving `flake.lock` (`nix flake update`) can change versions; run all three test scripts afterwards.
- `lustre_dev_tools` downloads its own Bun binary. That worked here but a dynamically linked download will probably not run on NixOS. If it
  fails there, set `tools.lustre.bin.bun = "system"` in `gleam.toml` (the shell provides bun). Not changed now, to leave the build for non-Nix users alone.
- Not tested on macOS or aarch64.
