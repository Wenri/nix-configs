{
  modulesPath,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./common-base.nix
    ./tailscale.nix
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  boot.kernelParams = [
    "fsck.mode=force"
    "fsck.repair=yes"
  ];

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Enable systemd-networkd for all machines
  # This provides modern network management with automatic IPv6 router discovery
  # networking.useNetworkd enables networkd and automatically disables dhcpcd
  networking.useNetworkd = true;

  # Enable QEMU guest tools for all machines (applies to both matnix and freenix)
  # This provides qemu-guest-agent and optimizations for running in QEMU/KVM
  services.qemuGuest.enable = true;
  
  services.resolved.enable = true;

  zramSwap = {
    enable = lib.mkDefault true;
    algorithm = lib.mkDefault "zstd";
    memoryPercent = lib.mkDefault 30;
  };

  # Enable systemd-oomd for OOM handling
  systemd.oomd.enable = true;
}
