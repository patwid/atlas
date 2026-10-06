# 0007. Declare the dev sandbox's network access as a committed sbx kit

- Status: Accepted
- Date: 2026-10-06
- Deciders: project owner

## Context

Development happens inside a Docker Sandbox (`sbx`) that blocks outbound traffic by default.
Atlas needs access to `repo.hex.pm` (Gleam packages) and `*.strava.com` (OAuth and API v3,
[ADR 0005](0005-wearable-data-integration.md)). Hosts can be allowed one at a time with
`sbx policy allow` or through the approval prompts, but those rules exist only on one machine
and are recorded nowhere.

## Decision

The required network allowlist lives in a mixin kit at `sbx/default/spec.yaml` (kit schema v2),
committed to the repo. It is applied to an existing sandbox with `sbx kit add`, or at creation with `--kit`.
New external hosts are added there, in the same commit as the code that needs them.

## Consequences

- The sandbox setup is reproducible and reviewed like any other code change.
- Only single-label wildcards (`*.strava.com`) are enforced in the current sbx release. `**` patterns
  are parsed but not yet enforced.
- `sbx kit add` restarts the sandbox. Running processes (for example a dev server) have to be started again.
