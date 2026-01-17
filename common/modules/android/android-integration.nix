# Android integration module for nix-on-droid
# Provides:
# - Android glibc/fakechroot build settings
# - replaceAndroidDependencies function (like NixOS replaceDependencies but using patchnar)
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

  # replaceAndroidDependencies - like NixOS replaceDependencies but for Android
  # Uses NAR serialization for atomic, clean patching:
  # 1. nix-store --dump -> serialize to NAR
  # 2. patchnar -> rewrite symlinks, patch ELF interpreter/RPATH, patch scripts
  # 3. nix-store --restore -> atomic output
  replaceAndroidDependencies = drv:
    pkgs.runCommand "${drv.name or "env"}-android"
    {
      nativeBuildInputs = [pkgs.nix patchnar];
    } ''
      nix-store --dump ${drv} | patchnar \
        --prefix "${installationDir}" \
        --glibc "${glibc}" \
        --gcc-lib "${gccLib}" \
        --old-glibc "${standardGlibc}" \
        --old-gcc-lib "${standardGccLib}" \
      | nix-store --restore $out
    '';

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
