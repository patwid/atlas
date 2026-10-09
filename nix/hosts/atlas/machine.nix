# Settings of this one machine, the Hetzner Cloud VPS (CX, x86_64, legacy BIOS). Taken over from the `vps` host of
# ~patwid/nixos-config (ADR 0094), which partitioned it with disko; the values below are what that configuration
# evaluated to, written out without disko because the disk is not partitioned again.
{ ... }:
{
  # GPT disk with a 1M BIOS-boot partition (EF02) for GRUB and one ext4 root partition.
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    fsType = "ext4";
    options = [ "defaults" ];
  };
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    devices = [ "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_122862218" ];
  };

  networking.hostName = "vps";
  # The network stack the server already runs; changing it during a deploy could cut the SSH connection.
  networking.networkmanager.enable = true;
  networking.nftables.enable = true;

  boot.tmp.useTmpfs = true;
  time.timeZone = "Europe/Zurich";

  # The NixOS release the server was installed with; never change it afterwards.
  system.stateVersion = "26.05";
}
