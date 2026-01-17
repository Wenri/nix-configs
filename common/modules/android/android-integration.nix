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

  # Standard glibc and gcc-lib from the base pkgs
  standardGlibc = pkgs.stdenv.cc.libc;
  standardGccLib = pkgs.stdenv.cc.cc.lib;

  # Patched gcc-lib with symlinks rewritten for Android
  gccLib = pkgs.runCommand "gcc-lib-android" {} ''
    cp -r ${standardGccLib} $out
    chmod -R u+w $out

    # Rewrite symlinks that point to /nix/store to use the Android prefix
    find $out -type l | while read -r link; do
      target=$(readlink "$link")
      if echo "$target" | grep -q "^/nix/store"; then
        new_target="${installationDir}$target"
        rm "$link"
        ln -s "$new_target" "$link"
      fi
    done || true
  '';

  # Import the NixOS-style grafting implementation
  replaceAndroidDepsLib = import ../../lib/replace-android-dependencies.nix {
    inherit lib;
    inherit (pkgs) runCommand writeText nix;
    inherit patchnar;
  };

  # replaceAndroidDependencies - NixOS-style grafting for Android
  # Uses IFD to discover closure, recursively patches all packages
  # with hash mapping for inter-package references
  replaceAndroidDependencies = drv:
    replaceAndroidDepsLib {
      inherit drv;
      prefix = installationDir;
      androidGlibc = glibc;
      androidGccLib = gccLib;
      inherit standardGlibc standardGccLib;
      cutoffPackages = [
        # Packages that shouldn't be patched (already Android-compatible)
        glibc
        gccLib
      ];
    };

in {
  options.android = {
    termuxTools = lib.mkEnableOption "Termux integration tools (am, termux-*, xdg-open)";
  };

  config = {
    # Android glibc build settings (always enabled)
    # Single-output glibc includes all binaries (iconv, locale needed by oh-my-zsh)
    # zsh added here so it's available in the patched environment.path for user shell
    environment.packages = [ glibc fakechroot gccLib pkgs.zsh ];
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
