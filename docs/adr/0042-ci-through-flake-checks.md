# 0042. Run the test suites as flake checks

- Status: Accepted
- Date: 2026-10-07
- Deciders: agent (owner asked whether CI could use Nix rather than shell scripts, and approved the proposal below)

## Context

[0041](0041-github-actions-ci.md) runs three of its four CI jobs as `nix develop --command bash -lc '<script>'`. That uses Nix only to install the tools:
every push runs every suite again, even when only docs changed, and the frontend-JS job reaches Hex, npm and the Bun download at test time.
The owner asked whether `scripts/build-frontend.sh` and the CI could be done with Nix instead of custom shell scripts.

## Options considered

1. **Move the frontend build into the flake and drop `build-frontend.sh`.** The script is also the dev build (it writes `backend/pb_public`, which a
   local PocketBase serves), the way the JS tests get the compiled Gleam in `frontend/build`, and the build for people without Nix ([0006](0006-toolchain-and-install.md)).
   Replacing it means two build recipes or making Nix mandatory, against the single recipe of [0033](0033-build-and-run-with-nix.md).
2. **Keep the scripts; make each test suite a flake check, and have CI build the checks.** A check is a derivation that builds only when its tests pass, so Nix
   caches the result by source and an unchanged suite is not run again. `nix flake check` is the same thing locally. The checks call the same scripts as everyone else.
3. **Leave CI as it is.** Works, but runs everything every time and is not offline.

## Decision

We will take option 2.

- `flake.nix` gets `checks.<system>`: `atlas-app` (the package), `gleam-test` (`gleam test`), `backend-test` (`scripts/test-backend.sh`) and `frontend-js-test`
  (`scripts/test-frontend-js.sh`). Each check's source is only what that suite reads (for example `backend-test` sees `backend/` and its script), so an edit
  elsewhere does not run it again.
- The checks build offline like `atlas-app`: Hex packages from `frontend/manifest.toml` ([0033](0033-build-and-run-with-nix.md)), Bun from nixpkgs, and the npm
  packages of `frontend/test-js` from its `package-lock.json` through nixpkgs' `importNpmLock`, which needs no extra hash in the flake. PocketBase listens on
  `127.0.0.1` inside the build sandbox.
- `scripts/test-frontend-js.sh` skips `npm install` when `ATLAS_NPM_INSTALL=0`; the check sets it and links the prebuilt `node_modules`. Without it the script behaves as before.
- Unchanged from 0041: GitHub Actions on `ubuntu-latest` only, triggered by pushes to `master` and every pull request (with in-progress runs on the same ref
  cancelled), Nix from `DeterminateSystems/nix-installer-action` and the store cached by `DeterminateSystems/magic-nix-cache-action`.
- `.github/workflows/ci.yml` has one job, `check`, with a matrix leg per check: `nix build .#checks.x86_64-linux.<check>`. The legs still pass or fail separately.

## Consequences

- An unchanged suite costs a cache lookup instead of a run, as far as the store cache on the runner (`magic-nix-cache-action`) holds the result.
- CI no longer reaches Hex or npm at test time except through fixed-output fetches; a new npm package needs only an updated `package-lock.json`.
- A test failure is a build failure; its output is in the build log (`--print-build-logs`, or `nix log` locally).
- A test that depends on something outside its check's source (a new file read from another directory) fails in the check until that path is added to its fileset.
- The CI job names changed from `build`, `gleam-test`, … to `check (atlas-app)`, `check (gleam-test)`, …; required status checks in branch protection must be updated.
- The checks run in the sandbox on Linux only as far as CI is concerned; on macOS the Nix sandbox is usually off, which has not been tried.
