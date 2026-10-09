# 0094. Atlas takes over the VPS from nixos-config

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (chose that atlas owns the VPS); agent (the details below)

## Context

[0091](0091-deploy-to-hetzner-with-caddy.md) puts the server's whole configuration in `nix/hosts/atlas` and expected its machine files to
be copied from the server. The server turned out to be the `vps` host of the owner's flake ~patwid/nixos-config (sourcehut), which also
configures four other machines and gives each of them about fifty shared modules: the `patwid` user with doas, Nix settings, NetworkManager,
nftables. Two flakes deploying one machine would overwrite each other.

## Options considered

1. **nixos-config imports the atlas module** and keeps deploying the VPS; atlas drops its host and deploy workflow.
2. **Atlas owns the VPS**: its settings move into atlas, and nixos-config no longer defines it. The shared modules are not on the server any more.
3. **Atlas extends nixos-config's `vps`** and deploys it; nixos-config must then never deploy it itself.

## Decision

Option 2.

- `nix/hosts/atlas/hardware-configuration.nix` is the VPS's file from nixos-config, unchanged. `machine.nix` writes out what disko and the shared
  modules produced for it, without disko (the disk is not partitioned again): root on `/dev/disk/by-partlabel/disk-main-root` (ext4), GRUB on
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_122862218` (legacy BIOS), host name `vps`, NetworkManager, nftables, `/tmp` on tmpfs, time zone
  Europe/Zurich, `stateVersion` 26.05. The file systems, boot loader, initrd modules, network stack, host name, state version, platform and SSH
  settings were evaluated in both flakes and are identical.
- NetworkManager stays because the server already uses it; replacing the network stack during a deploy could cut the connection.
- Access is root with the owner's three keys (desktop, htpc, laptop) plus the deploy key once it exists. The `patwid` user, doas and the
  `builds.sr.ht` key are gone from the server.
- `publicUrl` is `http://204.168.179.170` ([0092](0092-plain-http-on-the-ip-until-there-is-a-domain.md)).
- The first switch goes through `patwid`, the only login the old system offers: the server builds the system as a trusted Nix user, and doas
  activates it (`docs/deploy.md`). Every later deploy is root over SSH, as in 0091.
- The Deploy workflow is skipped while the variable `DEPLOY_HOST` is unset, so pushes before the GitHub environment exists do not fail.
- nixos-config gets a patch (outside this repository) that removes the `vps` host and the `vps` role and makes its SSH alias `vps` log in as root.

## Consequences

- The server's configuration is entirely in this repository; nixos-config changes no longer reach it.
- Tools and settings from the shared modules (shell, editors, packages, Nix registry) are not on the server; what it needs goes into `nix/hosts/atlas`.
- The system was evaluated, not built or booted: x86_64 cannot be built in the sandbox. The first switch is the test, with the Hetzner console
  and the previous GRUB entry as the way back.
