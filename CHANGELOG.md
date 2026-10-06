# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Design decisions live in [docs/adr](docs/adr/README.md). Entries link to the related ADR where there is one.

## [Unreleased]

### Added
- ADR process and the initial architecture decisions (ADR 0001–0006).
- Pinned toolchain (`.tool-versions`) and `scripts/install-tools.sh` for Gleam 1.19.0, Erlang/OTP 27 and PocketBase 0.40.4 (ADR 0006).
- `backend/` layout for PocketBase hooks, migrations and static files (ADR 0002, 0006).
- `sbx/default` sandbox kit that allows `repo.hex.pm` and Strava (ADR 0007).
- `sbxenv.yaml` to create and attach to the dev sandbox with `sbx env run` (ADR 0008).
- PocketBase migration with the data model and API rules: plans, workouts, assignments, activities, matches, coach grants and Strava connections (ADR 0009).
- `scripts/test-backend.sh` runs the API rule tests against a throwaway PocketBase (ADR 0009).
- `GET /api/atlas/users/lookup` to find a user by exact e-mail, so coaches and athletes can be selected for grants and assignments (ADR 0010).

### Changed
- Coach access to athletes' activities, including Strava-sourced data, now that Strava has confirmed the usage in writing (ADR 0005).
- ADRs 0003 and 0004 accepted.
