# 0033. Build and run the app with `nix build` and `nix run`

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner (asked to extend the flake so the app can be built and run with Nix)

## Context

[0032](0032-nix-flake-dev-shell.md) gave a development shell. The owner also wants `nix build` and `nix run`. A Nix build has no network access, but
the frontend build needs Hex packages ([0013](0013-app-shell-and-pwa-build.md)) and `lustre_dev_tools` downloads a Bun binary that would not run in the
build sandbox anyway.

## Decision

- **`packages.atlas-app`** builds the frontend with the same `scripts/build-frontend.sh` as everyone else, so there is one build recipe. It outputs
  `share/atlas/{pb_public,pb_hooks,pb_migrations}`.
- **Hex packages come from the lock file.** The flake reads `frontend/manifest.toml` and fetches each tarball from `repo.hex.pm`, checked against its
  `outer_checksum`. They are laid out as Gleam's download cache (whose file names are those checksums), so `gleam build` finds them offline. A new or
  upgraded dependency needs no change to the flake.
- **Bun from nixpkgs.** The build appends `[tools.lustre.bin] bun = "system"` to its own copy of `gleam.toml`; the file in the repository is unchanged,
  so the non-Nix build still downloads Bun. This settles the open point in 0032 for the Nix build only.
- **`build-frontend.sh`** reads two optional variables, `ATLAS_BUILD_ID` and `ATLAS_PUBLIC_OUT`. Without them it behaves as before. The Nix build
  id is the git revision plus the commit date, so the same commit gives the same service-worker cache name.
- **`packages.atlas`** (also `packages.default` and `apps.default`) is a launcher: PocketBase serving the three directories from the store, with
  `--hooksWatch=false --automigrate=false` because the store is read-only. Data lives in `$ATLAS_DATA_DIR`, else `$XDG_DATA_HOME/atlas`, else
  `~/.local/share/atlas`. Further arguments go to `pocketbase serve` (`nix run . -- --http=0.0.0.0:8090`). Strava settings come from the environment ([0012](0012-strava-integration-hooks.md)).
- The build source is `frontend/`, `backend/` and `scripts/build-frontend.sh`, minus the test directories, so edits to docs, CI or tests do not rebuild it. New files must be tracked in git (a flake only sees tracked files).

## Consequences

- Verified on 2026-10-06 (x86_64-linux, PocketBase 0.39.11): `nix build` offline; the launcher served the app, the single-page fallback, the migrated
  data model and the Strava routes; the 37 browser-side tests still pass with the changed script. The built `atlas.js` is made by Bun 1.4.2 from nixpkgs, not by the Bun that `lustre_dev_tools` downloads, so the bytes differ from `scripts/build-frontend.sh` output.
- Not tested: aarch64 or macOS builds; upgrading a database created by an older build (migrations are applied at start as with the scripts).
- Updating PocketBase through nixpkgs ([0032](0032-nix-flake-dev-shell.md) warns about the version) changes what `nix run` serves; run the backend tests first.
- No NixOS module yet: running as a service, TLS, backups and secrets are left to the host.
