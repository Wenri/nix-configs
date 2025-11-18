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
  boot.zfs.package = pkgs.zfs_unstable;
  boot.kernelPackages = pkgs.linuxPackages_xanmod_stable;
  boot.kernelParams = [
    "quiet"
    "splash"
    "mce=dont_log_ce"
    "nowatchdog"
    "tsc=nowatchdog"
    "nmi_watchdog=0"
    "nosoftlockup"
    "preempt=full"
    "retbleed=stuff"
  ];

  # for local disks that are not shared over the network, we don't need this to be random
  networking.hostId = "8425e349";
  # TODO: Set your hostname
  networking.hostName = "irif";

  # Only allowed NTP
  networking.timeServers = ["ntp.univ-paris-diderot.fr"];

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm = {
    enable = true;
    autoSuspend = false;
  };
  services.desktopManager.gnome.enable = true;

  # Swao Ctrl and Caps
  services.udev.extraHwdb = ''
    evdev:input:b0003v046Ap0023*
      KEYBOARD_KEY_70039=leftctrl # caps -> ctrl_l
      KEYBOARD_KEY_700e0=capslock # ctrl_l -> caps
  '';

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = lib.mkAfter (with pkgs; [
    htop
    libreoffice-qt
  ]);
  
  services.fwupd.enable = true;
  services.earlyoom.enable = true;

  virtualisation.docker.enable = true;

  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  networking.networkmanager.dispatcherScripts = [ {
    source = pkgs.writeText "50-tailscale" ''
        #!${pkgs.runtimeShell}
        interface="$1"
        event="$2"
        set -e
        [ "$event" == "up" ] || exit 0
        [ "$interface" == "enp0s31f6" ] ||  exit 0
        ${pkgs.ethtool}/bin/ethtool -K "$interface" rx-udp-gro-forwarding on rx-gro-list off
      '';
    type = "basic";
    }
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
