# NixOS module: Atlas as a systemd service (ADR 0090). The flake passes in its own packages, so the
# defaults are the built app and the PocketBase it is tested with, not whatever the host's nixpkgs has.
{ atlasPackages, flakePkgs }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.atlas;
  inherit (lib) mkOption mkEnableOption types;
  system = pkgs.stdenv.hostPlatform.system;
  stateDir = "/var/lib/atlas";

  # PocketBase pointed at the app and the service's data. The service runs it, and an admin runs it for the
  # CLI (`sudo atlas-pocketbase superuser upsert ...`); as root it switches to the service user first, so no
  # file in the data directory ends up owned by root.
  atlas-pocketbase = pkgs.writeShellApplication {
    name = "atlas-pocketbase";
    runtimeInputs = [ cfg.pocketbasePackage pkgs.util-linux ];
    text = ''
      if [ "$(id -u)" = 0 ]; then
        exec runuser -u ${cfg.user} -- "$0" "$@"
      fi
      exec pocketbase \
        --dir ${stateDir}/pb_data \
        --hooksDir ${cfg.package}/share/atlas/pb_hooks \
        --migrationsDir ${cfg.package}/share/atlas/pb_migrations \
        --publicDir ${cfg.package}/share/atlas/pb_public \
        --hooksWatch=false --automigrate=false \
        "$@"
    '';
  };
in
{
  options.services.atlas = {
    enable = mkEnableOption "Atlas, the running-training app (PocketBase serving the built frontend)";

    package = mkOption {
      type = types.package;
      default = atlasPackages.${system}.atlas-app;
      defaultText = lib.literalExpression "atlas.packages.\${system}.atlas-app";
      description = "The built app: frontend, PocketBase hooks and migrations.";
    };

    pocketbasePackage = mkOption {
      type = types.package;
      default = flakePkgs.${system}.pocketbase;
      defaultText = lib.literalExpression "atlas.inputs.nixpkgs.legacyPackages.\${system}.pocketbase";
      description = "The PocketBase that serves the app. The default is the one the flake's tests run against.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen on. Keep it local and put a reverse proxy with TLS in front.";
    };

    port = mkOption {
      type = types.port;
      default = 8090;
      description = "HTTP port.";
    };

    publicUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://atlas.example.org";
      description = "The public HTTPS origin (`ATLAS_PUBLIC_URL`). Strava's redirect and webhook need it.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/atlas.env";
      description = ''
        File with secret variables (`STRAVA_CLIENT_ID=...` lines), read by systemd when the service starts.
        Use a path outside the Nix store, which is world-readable: `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`,
        `STRAVA_VERIFY_TOKEN` and, after the one-time subscribe, `STRAVA_SUBSCRIPTION_ID`.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { ATLAS_PURGE_RETENTION_DAYS = "90"; };
      description = "Further non-secret environment variables for the hooks.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open `port` in the firewall. Only useful with a non-local `listenAddress`.";
    };

    user = mkOption {
      type = types.str;
      default = "atlas";
      description = "User and group the service runs as. It owns `/var/lib/atlas`.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = stateDir;
    };
    users.groups.${cfg.user} = { };

    environment.systemPackages = [ atlas-pocketbase ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.atlas = {
      description = "Atlas (PocketBase)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = cfg.environment // lib.optionalAttrs (cfg.publicUrl != null) {
        ATLAS_PUBLIC_URL = cfg.publicUrl;
      };

      serviceConfig = {
        # Pending migrations are applied when PocketBase starts, so an upgrade is a rebuild and a restart.
        ExecStart = "${lib.getExe atlas-pocketbase} serve --http=${
          if lib.hasInfix ":" cfg.listenAddress then "[${cfg.listenAddress}]" else cfg.listenAddress
        }:${toString cfg.port}";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        User = cfg.user;
        Group = cfg.user;
        StateDirectory = "atlas";
        StateDirectoryMode = "0700";
        WorkingDirectory = stateDir;
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;

        # Hardening: PocketBase only needs its data directory and the network.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        CapabilityBoundingSet = "";
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        SystemCallErrorNumber = "EPERM";
      };
    };
  };
}
