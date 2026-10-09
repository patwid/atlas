# The production server: a Hetzner Cloud VPS running NixOS (ADR 0091), deployed by .github/workflows/deploy.yml.
# What is specific to the machine (disks, boot loader, network, state version) is copied from the server into
# hardware-configuration.nix, machine.nix and, if the server has one, networking.nix; see docs/deploy.md.
{ lib, options, ... }:

let
  # Fill these in before the first deploy; the assertions below stop a deploy that still has the examples.
  # The address the app is reached at. With a domain, "https://atlas.example.org": Caddy gets a certificate.
  # Until there is a domain, "http://<the server's IPv4 address>": plain HTTP, see ADR 0092 for what that gives up.
  publicUrl = "https://atlas.example.org";
  # For Let's Encrypt; only needed with https.
  acmeEmail = "admin@example.org";
  sshKeys = [
    # The owner's own key, so the server stays reachable without CI.
    # "ssh-ed25519 AAAA... owner@laptop"
    # The deploy key whose private half is the DEPLOY_SSH_KEY secret of the GitHub environment `production`.
    # "ssh-ed25519 AAAA... atlas-deploy"
  ];

  https = lib.hasPrefix "https://" publicUrl;
in
{
  imports = [ ./hardware-configuration.nix ./machine.nix ]
    ++ lib.optional (builtins.pathExists ./networking.nix) ./networking.nix;

  assertions = [
    { assertion = publicUrl != "https://atlas.example.org"; message = "nix/hosts/atlas: set `publicUrl` to the server's address."; }
    {
      assertion = https -> acmeEmail != "admin@example.org";
      message = "nix/hosts/atlas: set `acmeEmail` for Let's Encrypt.";
    }
    { assertion = sshKeys != [ ]; message = "nix/hosts/atlas: add the owner's and the deploy SSH keys, or nobody can log in."; }
    {
      # Set by machine.nix, not left at the default, which follows nixpkgs and would change on an update.
      assertion = options.system.stateVersion.highestPrio < (lib.mkOptionDefault null).priority;
      message = "nix/hosts/atlas: copy system.stateVersion from the server into machine.nix.";
    }
  ];

  networking.hostName = lib.mkDefault "atlas";

  services.atlas = {
    enable = true;
    inherit publicUrl;
    # Created empty below; the Strava secrets are written into it by hand on the server (docs/deploy.md).
    environmentFile = "/var/lib/secrets/atlas.env";
    caddy.enable = true;
  };
  services.caddy.email = lib.mkIf https acmeEmail;

  # The secrets file exists from the first boot or deploy on, empty and readable by root only, so the service starts
  # before Strava is set up. `f` never touches the contents of an existing file, only its owner and mode.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets 0700 root root -"
    "f /var/lib/secrets/atlas.env 0600 root root -"
  ];

  # Deploys log in as root with a key; no passwords.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
  networking.firewall.enable = true;

  # The deploy builds on the server, so it needs flakes; old generations are cleaned up weekly.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  boot.loader.grub.configurationLimit = lib.mkDefault 10;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
}
