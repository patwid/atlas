# Deploying Atlas on NixOS

The flake has a NixOS module that runs Atlas as a systemd service ([ADR 0090](adr/0090-nixos-module.md)). TLS and
backups are up to the host; this page shows one way to do both.

## Host configuration

```nix
# flake.nix of the host
{
  inputs.atlas.url = "github:<owner>/atlas";

  outputs = { nixpkgs, atlas, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        atlas.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

```nix
# configuration.nix
{
  services.atlas = {
    enable = true;
    publicUrl = "https://atlas.example.org";
    environmentFile = "/var/lib/secrets/atlas.env";   # not in the Nix store
  };

  # TLS: Caddy gets a Let's Encrypt certificate and proxies to PocketBase on 127.0.0.1:8090.
  services.caddy = {
    enable = true;
    virtualHosts."atlas.example.org".extraConfig = ''
      reverse_proxy 127.0.0.1:8090
    '';
  };
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

The environment file holds the Strava secrets, one `NAME=value` per line, readable by root only:

```sh
STRAVA_CLIENT_ID=...
STRAVA_CLIENT_SECRET=...
STRAVA_VERIFY_TOKEN=...      # any random string, e.g. from `openssl rand -hex 24`
STRAVA_SUBSCRIPTION_ID=...   # added after step 3 below
```

Other options: `listenAddress`, `port`, `openFirewall`, `environment` (for example `ATLAS_PURGE_RETENTION_DAYS`),
`package` and `pocketbasePackage`.

## First start

1. **Superuser:** `sudo atlas-pocketbase superuser upsert you@example.org '<password>'`. The command runs as the
   service user, so the database stays owned by it. The admin UI is at `https://atlas.example.org/_/`.
2. **Accounts:** the app has no sign-up page; create users in the admin UI (`users` collection).
3. **Strava:** in the Strava API settings, set the authorization callback domain to `atlas.example.org`. Then
   subscribe to webhooks once, with a superuser token from the admin UI or from
   `POST /api/collections/_superusers/auth-with-password`:

   ```sh
   curl -X POST https://atlas.example.org/api/atlas/strava/subscribe -H "Authorization: <superuser token>"
   ```

   Put the returned id into `STRAVA_SUBSCRIPTION_ID` and restart: `systemctl restart atlas`.

## Data, backups and upgrades

- Everything lives in `/var/lib/atlas/pb_data` (SQLite database, uploads, logs), owned by `atlas`, mode 0700.
  The Strava tokens are stored there in plain text ([ADR 0012](adr/0012-strava-integration-hooks.md)).
- Backups: PocketBase's own backups (admin UI → Settings → Backups, with a schedule and optional S3 storage)
  copy the database consistently while the service runs. A file-level backup of `/var/lib/atlas` is only
  consistent with the service stopped.
- Upgrades: update the `atlas` input and rebuild. The service restarts, and PocketBase applies new migrations
  at start. Take a backup first.
- Logs: `journalctl -u atlas`.
