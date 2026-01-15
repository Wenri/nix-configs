# Android integration module for nix-on-droid
# Provides:
# - Android glibc/fakechroot build settings
# - replaceAndroidDependencies function (like NixOS replaceDependencies but using patchelf)
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

  # Installation directory from nix-on-droid build config
  inherit (config.build) installationDir;

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

  # replaceAndroidDependencies - like NixOS replaceDependencies but using patchelf
  # Takes a derivation and patches ALL ELF binaries and scripts for Android glibc
  # This is applied to the final environment, giving transitive dependency patching
  replaceAndroidDependencies = drv:
    pkgs.runCommand "${drv.name or "env"}-android"
    {
      nativeBuildInputs = [pkgs.patchelf pkgs.file];
    } ''
      # Step 1: Copy preserving symlinks (fast)
      cp -r ${drv} $out
      chmod -R u+w $out

      # Step 2: Handle symlinks - rewrite targets and dereference ELF files
      find $out -type l | while read -r link; do
        target=$(readlink "$link")

        # Skip broken symlinks that point to Android paths (glibc compat symlinks)
        if echo "$target" | grep -q "data/data/com.termux"; then
          # Make absolute and keep as symlink
          abs_target=$(echo "$target" | sed 's|.*/\(data/data/\)|/\1|')
          rm "$link"
          ln -sf "$abs_target" "$link" 2>/dev/null || true
          continue
        fi

        # For symlinks to /nix/store, check if target is ELF
        if echo "$target" | grep -q "^/nix/store"; then
          # Check if target exists and is ELF
          if [ -f "$target" ] && file "$target" 2>/dev/null | grep -q "ELF"; then
            # Dereference: replace symlink with copy of actual file
            rm "$link"
            cp "$target" "$link"
            chmod u+w "$link"
          else
            # Not ELF or doesn't exist - just add Android prefix
            new_target="${installationDir}$target"
            rm "$link"
            ln -s "$new_target" "$link"
          fi
        fi
      done || true

      # Step 3: Remove remaining dangling symlinks
      find $out -xtype l -delete 2>/dev/null || true

      # Patch script files (text files can handle any length change)
      find $out -type f | while read -r file; do
        if head -c 2 "$file" 2>/dev/null | grep -q "^#!"; then
          if grep -q "/nix/store" "$file" 2>/dev/null; then
            # Only add prefix if not already prefixed
            if ! grep -qF "${installationDir}/nix/store" "$file" 2>/dev/null; then
              sed -i "s|/nix/store|${installationDir}/nix/store|g" "$file"
            fi
          fi
        fi
      done || true

      # Patch ELF files (patchelf handles any length change for interpreter/RPATH)
      # Skip Go binaries - they have their own runtime and patching causes SIGSEGV
      find $out -type f | while read -r file; do
        if ! file "$file" 2>/dev/null | grep -q "ELF.*dynamic"; then
          continue
        fi

        # Skip Go binaries (detected by "Go build" string in binary)
        # Go binaries work fine with standard glibc on Android
        if grep -q "Go build" "$file" 2>/dev/null; then
          continue
        fi

        # Skip files that are part of our Android glibc/fakechroot (already correct)
        # These packages are already built for Android and shouldn't be modified
        case "$file" in
          *glibc-android*|*fakechroot-android*|*gcc-lib-android*)
            continue
            ;;
        esac

        INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || echo "")
        # Patch any interpreter that isn't already pointing to our Android glibc
        if [ -n "$INTERP" ] && ! echo "$INTERP" | grep -qF "${installationDir}${glibc}"; then
          NEW_INTERP="${installationDir}${glibc}/lib/ld-linux-aarch64.so.1"
          patchelf --set-interpreter "$NEW_INTERP" "$file" 2>/dev/null || true
        fi

        RPATH=$(patchelf --print-rpath "$file" 2>/dev/null || echo "")
        if [ -n "$RPATH" ] && echo "$RPATH" | grep -q "/nix/store"; then
          # Transform RPATH: replace glibc, gcc-lib, and add Android prefix
          NEW_RPATH=$(echo "$RPATH" | sed "s|${standardGlibc}|${glibc}|g")
          NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|${standardGccLib}|${gccLib}|g")
          NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|/nix/store|${installationDir}/nix/store|g")
          patchelf --set-rpath "$NEW_RPATH" "$file" 2>/dev/null || true
        elif [ -z "$RPATH" ] || ! echo "$RPATH" | grep -qF "${installationDir}"; then
          # Empty or non-Android RPATH - add essential Android library paths
          ANDROID_LIBS="${installationDir}${glibc}/lib:${installationDir}${gccLib}/lib"
          if [ -n "$RPATH" ]; then
            NEW_RPATH="$ANDROID_LIBS:$RPATH"
          else
            NEW_RPATH="$ANDROID_LIBS"
          fi
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
