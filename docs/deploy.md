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

### 2. The machine's settings (done)

The VPS (204.168.179.170, x86_64, legacy BIOS) used to be the `vps` host of ~patwid/nixos-config. Its machine settings
are now in `nix/hosts/atlas/` ([ADR 0094](adr/0094-atlas-owns-the-vps.md)): `hardware-configuration.nix` unchanged, and the
disk, GRUB, NetworkManager and `stateVersion` in `machine.nix`, checked to evaluate to the same values as before.
`default.nix` has `publicUrl = "http://204.168.179.170"` and your three SSH keys for root.

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

Do the first switch by hand, so you see it happen and can react. The server still runs the nixos-config system, where
root only accepts the builds.sr.ht key and you are `patwid` with doas (no sudo), so this one goes through `patwid`:
the server builds the system (patwid is a trusted Nix user), and doas activates it.

```sh
sys=$(nix build --no-link --print-out-paths --store ssh-ng://patwid@204.168.179.170 \
  .#nixosConfigurations.atlas.config.system.build.toplevel)
ssh -t patwid@204.168.179.170 \
  "doas sh -c 'nix-env -p /nix/var/nix/profiles/system --set $sys && $sys/bin/switch-to-configuration switch'"
```

The switch removes `patwid` and doas and lets root in with your keys; the open session keeps running. Check from a
second terminal that `ssh root@204.168.179.170` works before you close it. From then on (and for any later deploy by hand):

```sh
nix run nixpkgs#nixos-rebuild -- switch --flake .#atlas \
  --target-host root@204.168.179.170 --build-host root@204.168.179.170 --use-substitutes
```

### 6. Inside the app

1. **Superuser:** `ssh root@204.168.179.170 atlas-pocketbase superuser upsert you@example.org '<password>'`. The admin
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

**Rolling back:** `ssh root@204.168.179.170 nixos-rebuild switch --rollback`, or pick the previous generation in the boot
menu from the Hetzner console if the server no longer answers. Then revert the commit, or the next deploy brings it back.

## Data and backups

- Everything lives in `/var/lib/atlas/pb_data` (SQLite database, uploads, logs), owned by `atlas`, mode 0700. The
  Strava tokens are stored there in plain text ([ADR 0012](adr/0012-strava-integration-hooks.md)).
- PocketBase's own backups (admin UI → Settings → Backups, with a schedule and optional S3 storage) copy the database
  consistently while the service runs. Hetzner's server backups or snapshots copy the disk as it is at that moment,
  which is not guaranteed to be consistent for SQLite.
- Logs: `journalctl -u atlas` and `journalctl -u caddy`.
