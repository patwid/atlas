# 0093. Nix files under `nix/`, the flake at the top

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to move the Nix files under `nix/`, keeping `flake.nix` and `flake.lock` at the top)

## Context

The NixOS module and its VM test ([0090](0090-nixos-module.md)) were in `nixos/`, the server's configuration
([0091](0091-deploy-to-hetzner-with-caddy.md)) in `hosts/`. Together with the flake, Nix files took up three places at the top of the
repository.

## Decision

Every Nix file except `flake.nix` and `flake.lock` lives under `nix/`:

| Before | Now |
|--------|-----|
| `nixos/module.nix` | `nix/nixos/module.nix` |
| `nixos/test.nix` | `nix/nixos/test.nix` |
| `hosts/atlas/` | `nix/hosts/atlas/` |

The flake stays at the top, so every command keeps its form (`nix develop`, `nix build .#atlas-app`, `nixos-rebuild --flake .#atlas`) and a
host can use the repository as a flake input without `?dir=`. New Nix files go under `nix/` too.

## Consequences

- ADRs 0090–0092 name the old paths; this table translates them.
- Nothing that is built changed: the sources of the app and the test suites and the server's system derivation are the same as before the move.
