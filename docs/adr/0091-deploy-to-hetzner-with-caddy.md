# 0091. Deploy to a Hetzner VPS from GitHub Actions, behind Caddy

- Status: Accepted; plain HTTP on the IP is allowed until there is a domain, see [0092](0092-plain-http-on-the-ip-until-there-is-a-domain.md)
- Date: 2026-10-09
- Deciders: owner (Hetzner VPS with NixOS, a deploy workflow, Caddy as the reverse proxy for now); agent (the details below)

## Context

[0090](0090-nixos-module.md) runs Atlas as a NixOS service and left TLS and the deployment to the host. The owner has a Hetzner Cloud
VPS running NixOS and wants a deploy workflow and, for now, Caddy as the reverse proxy.

## Options considered

Where the server's configuration lives:

1. **In this repository** (`nixosConfigurations.atlas`): every change to the server is a reviewed commit, and a deploy is one
   `nixos-rebuild` against a known flake. The machine's own files have to be copied in once.
2. **Only on the server**, with the workflow updating an `atlas` input there and rebuilding: nothing machine-specific in the
   repository, but the server's configuration is unversioned.

How to deploy: `nixos-rebuild --target-host` over SSH (built into NixOS), or a tool such as deploy-rs or colmena (rollback on lost
connectivity, several hosts). One host does not need the extra tool.

The proxy: Caddy (automatic Let's Encrypt, a few lines of configuration) or nginx with the ACME module (more knobs, more lines).

## Decision

- **The server's configuration is in `hosts/atlas/`** (option 1). `default.nix` holds the deployment: Atlas, Caddy, SSH with keys
  only, the firewall, weekly garbage collection. `hardware-configuration.nix` and, if present, `networking.nix` are copied from the
  server; `machine.nix` takes its boot loader and `system.stateVersion`. `nixosConfigurations.atlas` only exists once
  `hardware-configuration.nix` is there, so the flake evaluates and its checks run before the server is set up. The system type comes
  from that file, so an x86 (CX/CPX/CCX) and an Arm (CAX) server work alike.
- **Guards**: assertions stop a deploy while the domain, ACME e-mail, SSH keys or state version are still missing; NixOS's own
  assertion catches a missing boot loader.
- **Caddy is an option of the module**, `services.atlas.caddy.enable`: it serves `publicUrl` with a Let's Encrypt certificate,
  compresses responses, sets `Strict-Transport-Security` (one year, no subdomains), `X-Content-Type-Options` and `Referrer-Policy`,
  drops the `Server` header, proxies to PocketBase on its local address, and opens 80 and 443 (TCP, UDP for HTTP/3). In the module
  rather than the host, so the VM test covers it (with `tls internal`).
- **`.github/workflows/deploy.yml`** runs after CI succeeds on a push to `master` (`workflow_run`, checking out the tested commit), or
  by hand. In the GitHub environment `production` it runs `nixos-rebuild switch --flake .#atlas` with the server as both target and
  build host, so the runner does not need the server's CPU type and the server fetches from cache.nixos.org itself. Afterwards it
  checks `<publicUrl>/api/health`. Deploys queue, they never cancel each other.
- **Access**: the workflow logs in as root with a deploy key (secret `DEPLOY_SSH_KEY`), checks the pinned host key
  (`DEPLOY_KNOWN_HOSTS`) and reads the address from the variable `DEPLOY_HOST`. Passwords are off.
- **Secrets stay on the server** in `/var/lib/secrets/atlas.env`, created by hand. A secrets tool (agenix, sops-nix) can come later.

## Consequences

- The server runs the flake's nixpkgs, which is unstable (0032). It changes only when `flake.lock` is updated, and CI tests that
  update first, but an update brings unstable's kernel and services to the server too.
- Building on the server uses its CPU and memory for a minute or two per deploy; the smallest VPS sizes are enough.
- `nixos-rebuild` does not roll back by itself if a deploy breaks SSH or networking; the way back is the Hetzner console and the
  previous boot generation (`docs/deploy.md`). deploy-rs's "magic rollback" would be the answer if that becomes a worry.
- The CI deploy key is as powerful as root on the server. The environment `production` can require the owner's approval per deploy.
- Open for the owner: the steps in `docs/deploy.md` (machine files, domain and e-mail, keys, DNS, GitHub environment, the secrets file,
  the first deploy by hand). Not tested: a real deploy, Let's Encrypt and Strava against the real domain. The server configuration was
  evaluated with a stand-in hardware configuration; the module and Caddy run in the VM test.
