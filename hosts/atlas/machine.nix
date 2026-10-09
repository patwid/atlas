# Settings of this one machine that are not in its hardware-configuration.nix. Copy them from the server's
# /etc/nixos/configuration.nix before the first deploy (docs/deploy.md); a wrong boot loader leaves it unbootable.
{ ... }:
{
  # The boot loader, exactly as on the server. Typical for Hetzner Cloud:
  #   x86 (CX, CPX, CCX), legacy BIOS:  boot.loader.grub.device = "/dev/sda";
  #   Arm (CAX), UEFI:                   boot.loader.systemd-boot.enable = true;
  #                                      boot.loader.efi.canTouchEfiVariables = true;

  # The NixOS release the server was installed with; never change it afterwards.
  # system.stateVersion = "25.05";
}
