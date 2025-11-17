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
    "luks-e8af78ec-280b-4662-9bbc-6bc27e1cc24a" = {
      device = "/dev/disk/by-uuid/e8af78ec-280b-4662-9bbc-6bc27e1cc24a";
      allowDiscards = true;
      keyFileSize = 4096;
      keyFile = "/dev/sr0";
      # optionally enable fallback to password in case USB is lost
      fallbackToPassword = true;
    };
    "luks-6a0ee6e9-7f65-43f2-b3df-4ef5ee243698" = {
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
  networking.hostName = "nixos-plasma6";
  
  # Enable the KDE Plasma Desktop Environment.
  services.displayManager = {
    sddm.enable = true;
    autoLogin.enable = true;
    autoLogin.user = "xsnow";
  };
  services.desktopManager.plasma6.enable = true;
  
  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
  
  virtualisation.vmware.guest.enable = true;
}
