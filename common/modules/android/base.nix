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

  # Get patchPackage from config (set by android-integration module)
  patchPkg = config.build.patchPackageForAndroidGlibc or (pkg: pkg);
in {
  # Environment packages for nix-on-droid (system-level)
  # Uses shared package lists from common/packages.nix
  # Note: These are automatically patched for Android glibc in path.nix
  # when build.patchPackageForAndroidGlibc is set
  environment.packages =
    packages.coreUtils
    ++ packages.compression
    ++ packages.networkTools
    ++ packages.systemTools
    ++ packages.editors
    ++ packages.modernCli
    ++ packages.devTools;
    # Note: fakechroot is now provided as androidFakechroot in flake.nix

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";

  # Read the changelog before changing this value
  system.stateVersion = "24.05";

  # Set up nix for flakes
  # Disable build-hook and builders: the default build-hook is broken on Android
  # because nix tries to run "ld.so __build-remote" but __build-remote is a nix
  # subcommand, not a standalone program
  nix.extraOptions = ''
    experimental-features = nix-command flakes
    build-hook =
    builders =
    pure-eval = false
  '';

  # User configuration (uses username from flake)
  # Shell needs explicit patching since it's not part of environment.packages
  user = {
    userName = username;
    group = username;
    shell = "${patchPkg pkgs.zsh}/bin/zsh";
  };

  # Set hostname in /etc/hosts
  networking.hosts = {
    "127.0.0.1" = [hostname];
  };

  # Note: Android environment variables (ANDROID_*, TERMUX_*, etc.) are sourced
  # via zsh's envExtra in hosts/nix-on-droid/home.nix, which handles both
  # Termux app sessions and SSH sessions uniformly.
}
