# Base nix-on-droid configuration
# Shared nix settings and environment configuration
{
  config,
  lib,
  pkgs,
  outputs,
  hostname,
  username,
  ...
}: let
  packages = import ../../packages.nix {inherit pkgs;};
in {
  # Environment packages for nix-on-droid (system-level)
  # Uses shared package lists from common/packages.nix
  # Note: time.timeZone (in locale.nix) creates /etc/zoneinfo symlink to tzdata
  environment.packages =
    packages.coreUtils
    ++ packages.compression
    ++ packages.networkTools
    ++ packages.systemTools
    ++ packages.editors
    ++ packages.modernCli
    ++ packages.devTools;

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";

  # Read the changelog before changing this value
  system.stateVersion = "24.05";

  # Set up nix for flakes
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # User configuration (uses username from flake)
  user = {
    userName = username;
    group = username;
    shell = "${pkgs.zsh}/bin/zsh";
  };

  # Set hostname in /etc/hosts
  networking.hosts = {
    "127.0.0.1" = [hostname];
  };

  # Note: Android environment variables (ANDROID_*, TERMUX_*, etc.) are sourced
  # via zsh's envExtra in hosts/nix-on-droid/home.nix, which handles both
  # Termux app sessions and SSH sessions uniformly.
}
