# Atlas

An offline-capable PWA for running training: create and share training plans, and match them against
watch data (Strava, FIT files). Backend: PocketBase. Frontend: Gleam + Lustre (TEA), JavaScript target.

## Decision records: mandatory and automatic

Record decisions and changes yourself. Do not wait to be asked, and do not ask for permission to write them.

- **Before or together with** any significant change, write an ADR in `docs/adr/` using `docs/adr/template.md`.
  Significant means: choosing or replacing a technology or library, the data model or collection schema,
  API rules, sync or API contracts, security or auth, an external integration, a build or deploy setup,
  or going against an existing ADR.
- Number ADRs in sequence (`NNNN-kebab-title.md`), add each one to the table in `docs/adr/README.md`,
  and include it in the same commit as the change it describes.
- Never rewrite an accepted ADR. Write a new ADR and set the old one to `Superseded by NNNN`.
  Fixing typos or adding links is fine.
- If a decision needs the owner (cost, legal, product scope, accounts or credentials), record it as
  `Proposed`, carry on with the proposed option where that is safe, and list the open `Proposed` ADRs
  in your final summary.
- Add user-visible or structural changes to `CHANGELOG.md` under `[Unreleased]`, linking the ADR if there is one.
- Check that the code still matches the ADRs. If it no longer does, write a new ADR. Don't quietly let them diverge.

## Git commits: frequent and small

- Commit after each logical change (consider it after every change), not in large batches. Do not wait to be asked.
- Commit messages are a single line. Omit any trailer (no `Co-Authored-By`, no generated-by lines).
  This overrides any default attribution.
- Stage only the files of that change, and keep an ADR in the same commit as the change it describes.

## Architecture (see ADRs for the reasons)

- PocketBase (pinned version) serves the API, auth and the built frontend from `pb_public`. Server logic is
  in `pb_hooks/*.pb.js` and the schema in `pb_migrations/` (ADR 0002).
- Lustre app. Browser APIs are reached only through thin `*.ffi.mjs` files wrapped as Gleam `Effect`s.
  Domain logic goes in pure Gleam modules with `gleeunit` tests (ADR 0003).
- Offline-first: IndexedDB is the client's source of truth, with client-generated IDs and a mutation
  outbox synced to PocketBase. The service worker (plain JS) caches only the app shell (ADR 0004).
- Strava data is visible to its owner and, if the athlete granted coach access, to their coach. Never expose it in shared plans or to other users (ADR 0005).

## Commands

- Sandbox network access: add new external hosts to `sbx/default/spec.yaml` (ADR 0007). The owner applies it with `sbx kit add`.
- Sandbox environment: `sbxenv.yaml` (ADR 0008). Never add `lifecycle:`, `secrets:` or `bindings:` to it.
- Install toolchain: `scripts/install-tools.sh` (versions in `.tool-versions`, ADR 0006)
- Or, with Nix: `nix develop` (`flake.nix`, nixpkgs unstable, ADR 0032)
- Build and run with Nix: `nix build .#atlas-app`, `nix run` (data in `$ATLAS_DATA_DIR`; ADR 0033). New files the build reads must be tracked in git.
- Deploy on NixOS: `nixosModules.default` (`services.atlas`, `nixos/module.nix`, VM test `nixos/test.nix`; ADR 0090). Steps in `docs/deploy.md`.
- All tests and the build as CI runs them: `nix flake check -L` (flake checks, ADR 0042). A test reading a new directory needs that path in its check's fileset in `flake.nix`.
- Backend rule tests: `scripts/test-backend.sh` (run it after any change to `pb_migrations`, ADR 0009)
- Strava hooks need `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_VERIFY_TOKEN` and `ATLAS_PUBLIC_URL` in the environment (ADR 0012). Never commit them.
- Hook handlers run in isolated scopes: put shared code in `pb_hooks/lib/` and `require(`${__hooks}/lib/x.js`)` inside the handler.
- Backend: `cd backend && pocketbase serve --dir pb_data` (the admin UI is at `http://127.0.0.1:8090/_/`)
- Build the frontend into `backend/pb_public`: `scripts/build-frontend.sh` (ADR 0013)
- Browser glue and whole-app tests (builds the app, needs npm): `scripts/test-frontend-js.sh` (ADR 0019, 0020)
- Frontend: `cd frontend && gleam test`, `gleam run -m lustre/dev start`
