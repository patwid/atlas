# 0041. Run CI on GitHub Actions through the Nix flake

- Status: Superseded by [0042](0042-ci-through-flake-checks.md)
- Date: 2026-10-07
- Deciders: agent (owner asked for GitHub CI; owner picked full-suite scope and a Linux-only runner over two narrower options)

## Context

There is no CI yet. Every build and test today runs on whoever's machine happens to run it, using either `scripts/install-tools.sh` (`.tool-versions`) or `nix develop` ([0032](0032-nix-flake-dev-shell.md)). A push or pull request gets no automated signal.

## Options considered

1. **Re-pin the toolchain on the runner directly** (an `asdf`-style setup from `.tool-versions`, or hand-picked `setup-*` actions for Gleam/Erlang/PocketBase/Node). Works without Nix, but is a second place the exact versions live, drifting from `flake.nix` over time.
2. **Run the Nix flake on the hosted runner** (`nix build .#atlas-app` for the package, `nix develop -c ...` for the test scripts). One source of truth for every version (`flake.nix` + `frontend/manifest.toml`), and the same commands contributors already run locally. Needs a Nix installer action and a store cache to keep runs fast, since the hosted runner starts cold every time.
3. **Build a container image from the flake and run CI inside it.** No real benefit over option 2 for a project this size, and adds an image build/push step to maintain.

## Decision

We will add `.github/workflows/ci.yml` with four independent jobs, all on `ubuntu-latest` (x86_64-linux, matching the dev/sandbox platform; `flake.nix`'s `aarch64-linux`/`darwin` outputs stay unverified by CI):

- **`build`** — `nix build .#atlas-app --print-build-logs`: proves the offline, fixed-output Hex-package build ([0033](0033-build-and-run-with-nix.md)) still works.
- **`gleam-test`** — `nix develop -c gleam test`: the pure Gleam unit tests ([0003](0003-use-gleam-lustre-frontend.md), [0015](0015-domain-core.md), [0016](0016-sync-core-outbox-and-cursor.md)).
- **`backend-test`** — `nix develop -c scripts/test-backend.sh`: the PocketBase API rule tests ([0009](0009-data-model-and-api-rules.md)).
- **`frontend-js-test`** — `nix develop -c scripts/test-frontend-js.sh`: builds the frontend and runs the browser-glue tests ([0019](0019-device-database.md), [0020](0020-sync-runner-and-conflicted-copies.md)). Unlike the `build` job, this step reaches the network the same way a normal `nix develop` session does (Hex, npm, the Bun binary `lustre_dev_tools` downloads).

Triggers: push to `master` and every pull request, with in-progress runs on the same ref cancelled when a new one starts. Nix is installed with `DeterminateSystems/nix-installer-action`, and `DeterminateSystems/magic-nix-cache-action` caches the Nix store between runs — no Cachix account or token needed.

Scope and platform were the owner's call: full suite (all four jobs) over build-only or build+gleam-test, and Linux-only over adding a `macos-latest` leg (macOS runners cost roughly 10x the Actions minutes of Linux).

## Consequences

- Every push and PR now gets build and test signal without needing a contributor's machine, using the exact same commands and versions as local `nix develop`.
- CI depends on two third-party actions (`DeterminateSystems/nix-installer-action`, `DeterminateSystems/magic-nix-cache-action`), pinned by major-version tag.
- `backend-test` and `frontend-js-test` reach the network (Hex, npm) and so are not fully offline/reproducible the way `build` is; a flaky registry can fail CI independently of the code.
- Not verified by CI: `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin` (the flake's other systems) — deliberately out of scope here; revisit if those platforms need a real signal.
- No binary cache for the *built* package itself beyond the Nix store cache; a cold cache rebuilds/refetches everything once, then subsequent runs reuse it.
