# Android integration module for nix-on-droid
# Provides:
# - Android glibc/fakechroot build settings
# - Package patching function (patchPackageForAndroidGlibc)
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

  # Installation directory for nix-on-droid (outside proot)
  installationDir = "/data/data/com.termux.nix/files/usr";

  # Get Android packages from common/pkgs
  androidPkgs = import ../../pkgs {
    inherit pkgs glibcSrc fakechrootSrc;
  };
  glibc = androidPkgs.androidGlibc;
  fakechroot = androidPkgs.androidFakechroot;

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

  # Function to patch a package for Android/nix-on-droid
  patchPackage = pkg:
    pkgs.runCommand "${pkg.pname or pkg.name or "package"}-android"
    ({
        nativeBuildInputs = [pkgs.patchelf pkgs.file];
        passthru = pkg.passthru or {};
      }
      // (
        if pkg ? meta.priority
        then {meta.priority = pkg.meta.priority;}
        else {}
      )) ''
      cp -r ${pkg} $out
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

      # Patch script files
      ORIG_STORE_PATH="${pkg}"
      find $out -type f | while read -r file; do
        if head -c 2 "$file" 2>/dev/null | grep -q "^#!"; then
          if grep -q "/nix/store" "$file" 2>/dev/null; then
            sed -i "s|$ORIG_STORE_PATH|$out|g" "$file"
            if ! grep -qF "${installationDir}/nix/store" "$file" 2>/dev/null; then
              sed -i "s|/nix/store|${installationDir}/nix/store|g" "$file"
            fi
          fi
        fi
      done || true

      # Patch ELF files
      find $out -type f | while read -r file; do
        if ! file "$file" 2>/dev/null | grep -q "ELF.*dynamic"; then
          continue
        fi

        INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || echo "")
        if [ -n "$INTERP" ] && echo "$INTERP" | grep -q "^/nix/store"; then
          NEW_INTERP="${installationDir}${glibc}/lib/ld-linux-aarch64.so.1"
          patchelf --set-interpreter "$NEW_INTERP" "$file" 2>/dev/null || true
        fi

        RPATH=$(patchelf --print-rpath "$file" 2>/dev/null || echo "")
        if [ -n "$RPATH" ] && echo "$RPATH" | grep -q "/nix/store"; then
          NEW_RPATH=$(echo "$RPATH" | sed "s|${standardGlibc}|${glibc}|g")
          NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|${standardGccLib}|${gccLib}|g")
          NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|/nix/store|${installationDir}/nix/store|g")
          patchelf --set-rpath "$NEW_RPATH" "$file" 2>/dev/null || true
        fi
      done || true
    '';
in {
  options.android = {
    termuxTools = lib.mkEnableOption "Termux integration tools (am, termux-*, xdg-open)";
  };

  config = {
    # Android glibc build settings (always enabled)
    environment.packages = [ glibc fakechroot gccLib ];
    build.androidGlibc = glibc;
    build.androidFakechroot = fakechroot;
    build.bashInteractive = patchPackage pkgs.bashInteractive;
    build.patchPackageForAndroidGlibc = patchPackage;
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
