# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other NixOS modules here
    imports = [
      # Shared desktop modules
      outputs.nixosModules.users
      outputs.nixosModules.locale
      outputs.nixosModules.secrets
      outputs.nixosModules.desktop-base

      # Import your generated (nixos-generate-config) hardware configuration
      ./hardware-configuration.nix
    ];

  # FIXME: Add the rest of your current configuration
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.initrd.luks.devices = {
    "luks-be8c7b36-0982-4e45-b7c1-0864ca83b166" = {
      device = "/dev/disk/by-uuid/be8c7b36-0982-4e45-b7c1-0864ca83b166";
      allowDiscards = true;
      keyFileSize = 4096;
      keyFile = "/dev/sr0";
      # optionally enable fallback to password in case USB is lost
      fallbackToPassword = true;
    };
    "luks-7f5e9ac8-ba4b-49f2-beb4-08931911ab29" = {
      allowDiscards = true;
      keyFileSize = 4096;
      keyFile = "/dev/sr0";
      # optionally enable fallback to password in case USB is lost
      fallbackToPassword = true;
    };
  };
  boot.zfs.package = pkgs.zfs_unstable;
  boot.kernelParams = [
    "quiet"
    "splash"
    "mce=off"
  ];
  
  # for local disks that are not shared over the network, we don't need this to be random
  networking.hostId = "8425e349";
  # TODO: Set your hostname
  networking.hostName = "nixos-gnome";
  
  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
  
  virtualisation.vmware.guest.enable = true;
}
