# Deploying Atlas

Atlas runs on a Hetzner Cloud VPS with NixOS, behind Caddy ([ADR 0090](adr/0090-nixos-module.md),
[ADR 0091](adr/0091-deploy-to-hetzner-with-caddy.md)). The server's whole configuration is in this repository
(`nix/hosts/atlas/`), and `.github/workflows/deploy.yml` switches the server to every `master` commit that passed CI.

**Address:** `https://atlas.patwid.ch` ([ADR 0099](adr/0099-https-on-atlas-patwid-ch.md)). DNS is at Infomaniak: an `A` record
for `atlas` to 204.168.179.170 and no `AAAA` record, because the server does not use its IPv6 address yet. Before the domain, it
ran on plain HTTP at its IP ([ADR 0092](adr/0092-plain-http-on-the-ip-until-there-is-a-domain.md)).

## One-time setup

### 1. DNS and the Hetzner firewall

- Point the domain at the server: an `A` record to its IPv4 address and, once the server has a public IPv6 address,
  an `AAAA` record to it. Never add an `AAAA` record the server does not answer on: Let's Encrypt tries IPv6 first.
- If the server is in a Hetzner Cloud firewall, allow TCP 22, 80 and 443, and UDP 443 (HTTP/3). Caddy needs port 80
  reachable to get its Let's Encrypt certificate.

### 2. The machine's settings (done)

The VPS (204.168.179.170, x86_64, legacy BIOS) used to be the `vps` host of ~patwid/nixos-config. Its machine settings
are now in `nix/hosts/atlas/` ([ADR 0094](adr/0094-atlas-owns-the-vps.md)): `hardware-configuration.nix` unchanged, and the
disk, GRUB, NetworkManager and `stateVersion` in `machine.nix`, checked to evaluate to the same values as before.
`default.nix` has `publicUrl = "https://atlas.patwid.ch"` and your three SSH keys for root.

Apply the handover patch to nixos-config (it removes the `vps` host there, so a rebuild from nixos-config can no
longer overwrite the server, and makes `ssh vps` log in as root):

```sh
cd nixos-config && git am ../nixos-config-vps-handover.patch
```

The deploy replaces the whole system: the `patwid` user, doas and the other shared nixos-config modules are no longer
on the server. Log in as `root` with your usual keys.

### 3. Deploy key and GitHub environment

```sh
ssh-keygen -t ed25519 -N '' -C atlas-deploy -f atlas-deploy   # atlas-deploy.pub goes into sshKeys
ssh-keyscan 204.168.179.170 > known_hosts
```

In the GitHub repository, under Settings → Environments, create `production` with:

- secret `DEPLOY_SSH_KEY`: the contents of `atlas-deploy` (the private key), then delete the local file;
- secret `DEPLOY_KNOWN_HOSTS`: the contents of `known_hosts`;
- variable `DEPLOY_HOST`: `204.168.179.170`. Until it is set, the Deploy workflow is skipped.

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

After changing it: `ssh root@204.168.179.170 systemctl restart atlas`.

### 5. First deploy, from your laptop

Do the first switch by hand, so you see it happen and can react. Root on the server already accepts your key, so the
deploy goes straight to root; the server builds the system itself.

First check that you can log in, and that the key you use is one of the three in `sshKeys`: after the switch, root
accepts only those.

```sh
ssh root@204.168.179.170 'nixos-version; uname -m'
```

Then build and switch. `boot` instead of `switch` activates the new system only on the next reboot, if you prefer
to restart into it from the Hetzner console.

```sh
nix run nixpkgs#nixos-rebuild -- switch --flake .#atlas \
  --target-host root@204.168.179.170 --build-host root@204.168.179.170 --use-substitutes
```

The switch removes `patwid` and doas; the open session keeps running. Before you close it, check from a second
terminal that `ssh root@204.168.179.170` still works and that `curl -fsS https://atlas.patwid.ch/api/health` answers.
Later deploys by hand use the same command.

### 6. Inside the app

1. **Superuser:** `ssh root@204.168.179.170 atlas-pocketbase superuser upsert you@example.org '<password>'`. The admin
   UI is at `<publicUrl>/_/`.
2. **Behind the proxy:** in the admin UI, Settings → Application, set the trusted proxy header to `X-Forwarded-For`,
   so logs and rate limits see the visitor's address instead of Caddy's.
3. **Accounts:** the app has no sign-up page; create users in the admin UI (`users` collection).
4. **Strava:** in the Strava API settings, set the authorization callback domain to `atlas.patwid.ch`. Subscribe to webhooks
   once, with a superuser token (from the admin UI or `POST /api/collections/_superusers/auth-with-password`):

   ```sh
   curl -X POST https://atlas.patwid.ch/api/atlas/strava/subscribe -H "Authorization: <superuser token>"
   ```

   Put the returned id into `STRAVA_SUBSCRIPTION_ID` and restart the service.

## Every deploy

A push to `master` runs CI; when it passes, the Deploy workflow evaluates the server's configuration, has the server
build and switch to it over SSH, and checks `<publicUrl>/api/health`. It can also be started by hand (Actions →
Deploy → Run workflow). PocketBase applies new migrations when it starts, so take a backup before a deploy that adds one.

**Rolling back:** `ssh root@204.168.179.170 nixos-rebuild switch --rollback`, or pick the previous generation in the boot
menu from the Hetzner console if the server no longer answers. Then revert the commit, or the next deploy brings it back.

## Data and backups

- Everything lives in `/var/lib/atlas/pb_data` (SQLite database, uploads, logs), owned by `atlas`, mode 0700. The
  Strava tokens are stored there in plain text ([ADR 0012](adr/0012-strava-integration-hooks.md)).
- PocketBase's own backups (admin UI → Settings → Backups, with a schedule and optional S3 storage) copy the database
  consistently while the service runs. Hetzner's server backups or snapshots copy the disk as it is at that moment,
  which is not guaranteed to be consistent for SQLite.
- Logs: `journalctl -u atlas` and `journalctl -u caddy`.
