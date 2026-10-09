# 0090. Run Atlas on NixOS with a module and a systemd unit

- Status: Accepted; TLS and deployment are now covered by [0091](0091-deploy-to-hetzner-with-caddy.md)
- Date: 2026-10-09
- Deciders: owner (asked for a NixOS module with a systemd unit); agent (the details below)

## Context

[0033](0033-build-and-run-with-nix.md) builds the app and gives a launcher for `nix run`, but left running it as a service, TLS, backups and
secrets to the host. The owner deploys on NixOS.

## Options considered

1. **A NixOS module in the flake** (`nixosModules.default`): the host imports it and sets `services.atlas`. Fits a NixOS host; the unit,
   user and hardening live next to the code they run.
2. **A plain systemd unit file** for any Linux host. Works anywhere, but the paths into the Nix store have to be filled in by hand.
3. **A container image.** Another layer to maintain, and NixOS does not need it.

## Decision

We add option 1, in `nixos/module.nix`.

- **Options**: `enable`, `package` (default: the flake's `atlas-app`), `pocketbasePackage` (default: the PocketBase of the *flake's*
  nixpkgs, which the tests ran against, not the host's), `listenAddress` (default `127.0.0.1`), `port` (8090), `publicUrl`
  (`ATLAS_PUBLIC_URL`), `environmentFile` (the Strava secrets, read by systemd, never in the store), `environment` (other variables such as
  `ATLAS_PURGE_RETENTION_DAYS`), `openFirewall` (off) and `user` (`atlas`).
- **Service**: `pocketbase serve` on the store's hooks, migrations and frontend, with `--hooksWatch=false --automigrate=false` as in 0033.
  Data in `/var/lib/atlas/pb_data` (`StateDirectory`, mode 0700, umask 0077). `Restart=on-failure`. Pending migrations run at start, so an
  upgrade is a rebuild.
- **A static system user**, not `DynamicUser`, so an admin can run the PocketBase CLI on the same data. The module installs
  `atlas-pocketbase`, PocketBase with the service's directories; run as root it switches to the service user first, so
  `sudo atlas-pocketbase superuser upsert ...` cannot leave root-owned files behind.
- **Hardening**: no capabilities, read-only system (`ProtectSystem=strict`), no home directories, private `/tmp` and devices, only IP and
  Unix sockets, `@system-service` system calls without `@privileged`, `MemoryDenyWriteExecute`.
- **TLS and backups stay with the host.** PocketBase listens locally and a reverse proxy terminates TLS; `docs/deploy.md` shows Caddy.
  Backups use PocketBase's own scheduled backups, which are consistent while the service runs.
- **Test**: `checks.<linux>.nixos-module` boots a VM with the module (`nixos/test.nix`): the app and service worker are served, the port is
  local only, the CLI writes as `atlas`, migrations ran, the hooks see the environment file (Strava reports `configured`), and data survives
  a restart. CI runs it as its own leg.

## Consequences

- Deploying is importing the module and setting a few options; the remaining steps (superuser, accounts, Strava subscription) are in
  `docs/deploy.md`.
- The Strava tokens stay in plain text in the database (0012); the 0700 data directory and the service user limit who can read them.
- Hosts that are not NixOS still have only `nix run` (0033). A plain unit file or image would be a new ADR.
- Verified on 2026-10-09: the VM test passes on aarch64-linux (PocketBase 0.39.11 from the flake's nixpkgs), run without KVM, so QEMU
  emulated the CPU (about 100 seconds for the script, plus boot). The x86_64-linux leg is first run by CI.
- The VM test needs KVM to be quick. Nix only schedules it on builders that declare the `kvm` feature; a builder without KVM can still
  run it by declaring the feature (`--option system-features "nixos-test kvm"`), as was done above.
