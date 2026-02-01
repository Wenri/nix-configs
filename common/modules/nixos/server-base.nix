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

  swapDevices = lib.mkDefault [
    { device = "/swapfile"; size = 2 * 1024; }
  ];

  zramSwap = {
    enable = lib.mkDefault true;
    algorithm = lib.mkDefault "zstd";
    memoryPercent = lib.mkDefault 30;
  };

  virtualisation.docker.enable = true;
  # Enable systemd-oomd for OOM handling
  systemd.oomd.enable = true;
}
