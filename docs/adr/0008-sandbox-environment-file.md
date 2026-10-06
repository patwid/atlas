# 0008. Start the dev sandbox from a committed `sbxenv.yaml`

- Status: Accepted
- Date: 2026-10-06
- Deciders: project owner

## Context

[ADR 0007](0007-sandbox-network-policy-as-kit.md) put the network allowlist in the kit `sbx/default`.
The owner wants the whole sandbox defined declaratively, so that `sbx env run` creates or attaches
to it. Docker's documentation recommends keeping `sbxenv.yaml` outside directories mounted into the
sandbox. Only the repository is mounted here, so the file would have to sit in the repository.

## Decision

`sbxenv.yaml` lives at the repo root (schema v1). It sets the agent (`claude`), the name `claude-atlas`,
mounts the repo as the workspace, and includes the `./sbx/default` kit.

Because the agent can write to this file, it must never contain:
- `lifecycle:` hooks, which run on the **host**
- `secrets:` or `bindings:`

Credentials stay in `sbx secret`. Changes to `sbxenv.yaml` and `sbx/` get extra scrutiny in review.

## Consequences

- The sandbox setup is versioned and can be reproduced with one command.
- `sbx env run` re-attaches to an existing sandbox **without re-provisioning**. Kit changes reach an
  existing sandbox only through `sbx kit add` or by recreating the sandbox.
- If host commands or secrets are ever needed, they go in a second, host-only env file that is merged
  in (`sbx env run . ~/atlas.local.sbxenv.yaml`). That file is not committed.
