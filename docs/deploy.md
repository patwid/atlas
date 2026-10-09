# Deploying Atlas

Atlas runs on a Hetzner Cloud VPS with NixOS, behind Caddy ([ADR 0090](adr/0090-nixos-module.md),
[ADR 0091](adr/0091-deploy-to-hetzner-with-caddy.md)). The server's whole configuration is in this repository
(`nix/hosts/atlas/`), and `.github/workflows/deploy.yml` switches the server to every `master` commit that passed CI.

**Without a domain, for now** ([ADR 0092](adr/0092-plain-http-on-the-ip-until-there-is-a-domain.md)): set `publicUrl` to
`http://<the server's IPv4 address>` and skip the DNS records, `acmeEmail` and the Strava steps. Caddy then serves plain HTTP
on port 80. Passwords travel unencrypted, so use test accounts only; the app also does not open offline and Strava cannot be
connected. `https://<ip-with-dashes>.sslip.io` (for example `https://203-0-113-10.sslip.io`) gives real HTTPS without a domain
of your own; everything below then works as with a domain.

## One-time setup

### 1. DNS and the Hetzner firewall

- Point the domain at the server: an `A` record to its IPv4 address and an `AAAA` record to its IPv6 address
  (not needed for `http://<IP>` or sslip.io).
- If the server is in a Hetzner Cloud firewall, allow TCP 22, 80 and 443, and UDP 443 (HTTP/3). Caddy needs port 80
  reachable to get its Let's Encrypt certificate.

### 2. Copy the machine's own settings into the repository

The deploy replaces the server's `/etc/nixos` configuration with `nix/hosts/atlas/`, so what is specific to the machine
has to come along. From your laptop:

```sh
scp root@<server>:/etc/nixos/hardware-configuration.nix nix/hosts/atlas/
scp root@<server>:/etc/nixos/networking.nix nix/hosts/atlas/   # only if it exists (nixos-infect writes one)
ssh root@<server> cat /etc/nixos/configuration.nix         # read it for the next step
```

- In `nix/hosts/atlas/machine.nix`, set the **boot loader** and **`system.stateVersion`** exactly as in that
  `configuration.nix`. Anything else in it you want to keep (swap, extra users, packages) goes there too.
- Check that `hardware-configuration.nix` sets `nixpkgs.hostPlatform` (`x86_64-linux`, or `aarch64-linux` on CAX);
  add it if your file is older and lacks it.
- In `nix/hosts/atlas/default.nix`, set `publicUrl` (`https://<domain>`, or `http://<IP>` for now), `acmeEmail` (only
  for https) and `sshKeys`: your own public key, and the deploy key from step 3. Without your key in `sshKeys`, the
  first deploy locks you out of SSH.

`nix eval .#nixosConfigurations.atlas.config.system.build.toplevel.drvPath` lists anything still missing.

### 3. Deploy key and GitHub environment

```sh
ssh-keygen -t ed25519 -N '' -C atlas-deploy -f atlas-deploy   # atlas-deploy.pub goes into sshKeys
ssh-keyscan <server> > known_hosts
```

In the GitHub repository, under Settings → Environments, create `production` with:

- secret `DEPLOY_SSH_KEY`: the contents of `atlas-deploy` (the private key), then delete the local file;
- secret `DEPLOY_KNOWN_HOSTS`: the contents of `known_hosts`;
- variable `DEPLOY_HOST`: the server's IP address or host name.

Optionally add yourself as a required reviewer, so every deploy waits for your approval.

### 4. Secrets on the server

The Strava secrets never go into the repository. NixOS creates `/var/lib/secrets/atlas.env` empty (mode 0600, root
only) on the first deploy, and Atlas runs without Strava until you fill it in. Nothing to do now; once the Strava app
exists, write these lines into it on the server:

```sh
STRAVA_CLIENT_ID=...
STRAVA_CLIENT_SECRET=...
STRAVA_VERIFY_TOKEN=...      # any random string, e.g. from `openssl rand -hex 24`
STRAVA_SUBSCRIPTION_ID=...   # added after the subscribe step below
```

After changing it: `ssh root@<server> systemctl restart atlas`.

### 5. First deploy, from your laptop

Do the first switch by hand, so you see it happen and can react:

```sh
nix run nixpkgs#nixos-rebuild -- switch --flake .#atlas \
  --target-host root@<server> --build-host root@<server> --use-substitutes
```

Then commit `nix/hosts/atlas/` and push; from then on the workflow deploys.

### 6. Inside the app

1. **Superuser:** `ssh root@<server> atlas-pocketbase superuser upsert you@example.org '<password>'`. The admin
   UI is at `<publicUrl>/_/`.
2. **Behind the proxy:** in the admin UI, Settings → Application, set the trusted proxy header to `X-Forwarded-For`,
   so logs and rate limits see the visitor's address instead of Caddy's.
3. **Accounts:** the app has no sign-up page; create users in the admin UI (`users` collection).
4. **Strava:** in the Strava API settings, set the authorization callback domain to your domain. Subscribe to webhooks
   once, with a superuser token (from the admin UI or `POST /api/collections/_superusers/auth-with-password`):

   ```sh
   curl -X POST https://<domain>/api/atlas/strava/subscribe -H "Authorization: <superuser token>"
   ```

   Put the returned id into `STRAVA_SUBSCRIPTION_ID` and restart the service.

## Every deploy

A push to `master` runs CI; when it passes, the Deploy workflow evaluates the server's configuration, has the server
build and switch to it over SSH, and checks `<publicUrl>/api/health`. It can also be started by hand (Actions →
Deploy → Run workflow). PocketBase applies new migrations when it starts, so take a backup before a deploy that adds one.

**Rolling back:** `ssh root@<server> nixos-rebuild switch --rollback`, or pick the previous generation in the boot
menu from the Hetzner console if the server no longer answers. Then revert the commit, or the next deploy brings it back.

## Data and backups

- Everything lives in `/var/lib/atlas/pb_data` (SQLite database, uploads, logs), owned by `atlas`, mode 0700. The
  Strava tokens are stored there in plain text ([ADR 0012](adr/0012-strava-integration-hooks.md)).
- PocketBase's own backups (admin UI → Settings → Backups, with a schedule and optional S3 storage) copy the database
  consistently while the service runs. Hetzner's server backups or snapshots copy the disk as it is at that moment,
  which is not guaranteed to be consistent for SQLite.
- Logs: `journalctl -u atlas` and `journalctl -u caddy`.
