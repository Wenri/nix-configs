# Android/nix-on-droid utilities
#
# This module provides all the infrastructure needed for running Nix packages
# on Android via nix-on-droid:
#
# - Android-patched glibc (with Termux patches for seccomp compatibility)
# - Package patching function (rewrites interpreter/RPATH for Android)
# - Patched gcc-lib (with rewritten symlinks)
# - Fakechroot builder
#
# Usage:
#   let
#     android = import ./common/lib/android.nix {
#       inherit pkgs;
#       glibcSrc = ./submodules/glibc;
#       fakechrootSrc = ./submodules/fakechroot;
#     };
#   in {
#     packages = [ android.glibc android.fakechroot android.gccLib ];
#     patchedPkg = android.patchPackage somePkg;
#   }
{
  pkgs,
  glibcSrc,
  fakechrootSrc,
}: let
  # Installation directory for nix-on-droid (outside proot)
  installationDir = "/data/data/com.termux.nix/files/usr";

  # Build Android-patched glibc using the Termux patches
  # Uses glibc 2.40 from submodules/glibc with Android-specific patches
  glibc = let
    glibcOverlay = import ../overlays/glibc.nix {
      inherit glibcSrc;
    } pkgs pkgs;
  in
    glibcOverlay.glibc;

  # Standard glibc and gcc-lib from the base pkgs
  standardGlibc = pkgs.stdenv.cc.libc;
  standardGccLib = pkgs.stdenv.cc.cc.lib;

  # Patched gcc-lib with symlinks rewritten for Android
  # gcc-lib contains symlinks to gcc-libgcc that point to /nix/store/...
  # We need to rewrite these to /data/data/.../nix/store/...
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

  # Function to patch a package for Android/nix-on-droid:
  # 1. Replace standard glibc with Android glibc in interpreter and RPATH
  # 2. Prefix ALL /nix/store paths with Android installation directory
  #    (needed because ld.so filters RUNPATH entries that don't exist,
  #    and /nix/store doesn't exist on Android)
  # 3. Preserve symlink structure (important for packages like cursor-cli)
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
      # Copy the entire package, preserving symlinks (no -L flag!)
      # This is important for packages like cursor-cli where bin/cmd -> ../share/app/cmd
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

      # Find and patch script files (hashbangs and /nix/store paths in content)
      # IMPORTANT: First replace self-references (to original package) with $out,
      # then prefix remaining /nix/store paths with Android installation directory
      ORIG_STORE_PATH="${pkg}"  # Original package store path

      find $out -type f | while read -r file; do
        # Check if it's a text file with a hashbang
        if head -c 2 "$file" 2>/dev/null | grep -q "^#!"; then
          # It's a script - patch paths in the content
          if grep -q "/nix/store" "$file" 2>/dev/null; then
            # Step 1: Replace self-references (original package path) with $out
            # This ensures wrapper scripts call their own patched binaries
            sed -i "s|$ORIG_STORE_PATH|$out|g" "$file"
            # Step 2: Prefix remaining /nix/store paths with Android prefix
            # BUT skip if already prefixed (locally-built packages already have Android paths)
            if ! grep -qF "${installationDir}/nix/store" "$file" 2>/dev/null; then
              sed -i "s|/nix/store|${installationDir}/nix/store|g" "$file"
            fi
          fi
        fi
      done || true

      # Find and patch all ELF files
      find $out -type f | while read -r file; do
        # Skip if not ELF
        if ! file "$file" 2>/dev/null | grep -q "ELF.*dynamic"; then
          continue
        fi

        # Patch interpreter to use Android-prefixed path
        INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || echo "")
        if [ -n "$INTERP" ] && echo "$INTERP" | grep -q "^/nix/store"; then
          # Use Android glibc's ld.so with full Android prefix
          NEW_INTERP="${installationDir}${glibc}/lib/ld-linux-aarch64.so.1"
          patchelf --set-interpreter "$NEW_INTERP" "$file" 2>/dev/null || true
        fi

        # Patch RPATH: prefix all /nix/store paths with Android installation directory
        # Also redirect standard glibc to Android glibc, and gcc-lib to patched version
        RPATH=$(patchelf --print-rpath "$file" 2>/dev/null || echo "")
        if [ -n "$RPATH" ] && echo "$RPATH" | grep -q "/nix/store"; then
          # First, redirect standard glibc to Android glibc
          NEW_RPATH=$(echo "$RPATH" | sed "s|${standardGlibc}|${glibc}|g")
          # Replace standard gcc-lib with patched version (has rewritten symlinks)
          NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|${standardGccLib}|${gccLib}|g")
          # Then, prefix all /nix/store paths with Android installation directory
          NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|/nix/store|${installationDir}/nix/store|g")
          patchelf --set-rpath "$NEW_RPATH" "$file" 2>/dev/null || true
        fi
      done || true
    '';

  # Build Android-patched fakechroot
  # All paths are hardcoded at compile time - no env vars needed
  fakechroot = import ../pkgs/android-fakechroot.nix {
    inherit (pkgs) stdenv patchelf fakechroot;
    androidGlibc = glibc;
    inherit installationDir;
    src = fakechrootSrc;
  };
in {
  # The pkgs set used for building (with overlays)
  inherit pkgs;

  # Constants
  inherit installationDir;

  # Packages
  inherit glibc gccLib fakechroot;

  # For backward compatibility / clarity
  androidGlibc = glibc;
  androidGccLib = gccLib;
  androidFakechroot = fakechroot;

  # Standard gcc-lib reference (needed for some configs)
  inherit standardGccLib;

  # Functions
  inherit patchPackage;

  # Alias for backward compatibility
  patchPackageForAndroidGlibc = patchPackage;
}
