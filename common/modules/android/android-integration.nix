# Android integration module for nix-on-droid
# Provides:
# - Android glibc/fakechroot build settings
# - replaceAndroidDependencies function (NixOS-style grafting with patchnar)
# - Termux integration tools
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.android;

  # Source paths relative to this module
  glibcSrc = ../../../submodules/glibc;
  fakechrootSrc = ../../../submodules/fakechroot;
  patchnarSrc = ../../../submodules/patchnar;

  # Installation directory from nix-on-droid build config
  inherit (config.build) installationDir;

  # Get Android packages from common/pkgs
  androidPkgs = import ../../pkgs {
    inherit pkgs glibcSrc fakechrootSrc patchnarSrc;
  };
  glibc = androidPkgs.androidGlibc;
  fakechroot = androidPkgs.androidFakechroot;
  patchnar = androidPkgs.patchnar;

  # Standard glibc from the base pkgs (gcc-lib is patched through normal grafting)
  standardGlibc = pkgs.stdenv.cc.libc;

  # Import the NixOS-style grafting implementation (local to this module)
  replaceAndroidDepsLib = import ./replace-android-dependencies.nix {
    inherit lib;
    inherit (pkgs) runCommand writeText nix sourceHighlight;
    inherit patchnar;
  };

  # replaceAndroidDependencies - NixOS-style grafting for Android
  # Uses IFD to discover closure, recursively patches all packages
  # with hash mapping for inter-package references
  # gcc-lib is patched through normal grafting (hash mapping handles it)
  #
  # Arguments:
  #   drv: the derivation to patch
  #   addPrefixToPaths (optional): list of additional paths to prefix in script strings
  #                                (e.g., ["/nix/var/"] for nix.sh)
  replaceAndroidDependencies = drv: { addPrefixToPaths ? [] }:
    replaceAndroidDepsLib {
      inherit drv addPrefixToPaths;
      prefix = installationDir;
      androidGlibc = glibc;
      inherit standardGlibc;
      cutoffPackages = [
        # Only glibc is cutoff (special Android build)
        # gcc-lib is patched through normal grafting
        glibc
      ];
    };

in {
  options.android = {
    termuxTools = lib.mkEnableOption "Termux integration tools (am, termux-*, xdg-open)";
  };

  config = {
    # Android glibc build settings (always enabled)
    # Multi-output glibc: out (libraries) + bin (iconv, locale needed by oh-my-zsh)
    # zsh added here so it's available in the patched environment.path for user shell
    # gcc-lib is patched through grafting (no longer needs manual android version)
    environment.packages = [ glibc glibc.bin fakechroot pkgs.zsh ];
    build.androidGlibc = glibc;
    build.androidFakechroot = fakechroot;
    # Environment-level patching (like NixOS replaceDependencies)
    # Patches entire environment at once - no per-package -android variants needed
    build.replaceAndroidDependencies = replaceAndroidDependencies;
    # Use patched environment.path for shells (bashInteractive already in path.nix)
    build.bashInteractive = config.environment.path;
    environment.etc."ld.so.preload".text = ''
      ${installationDir}${fakechroot}/lib/fakechroot/libfakechroot.so
    '';

    # Termux tools (optional)
    android-integration = lib.mkIf cfg.termuxTools {
      am.enable = true;
      termux-open.enable = true;
      termux-open-url.enable = true;
      termux-setup-storage.enable = true;
      termux-reload-settings.enable = true;
      termux-wake-lock.enable = true;
      termux-wake-unlock.enable = true;
      xdg-open.enable = true;
    };
  };
}
