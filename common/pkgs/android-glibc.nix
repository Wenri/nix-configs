# Android glibc package builder
# Uses pre-patched glibc from submodules/glibc with nixpkgs + Termux Android patches
# Based on: https://github.com/termux-pacman/glibc-packages/tree/main/gpkg/glibc
#
# IMPORTANT: Both nixpkgs and Termux patches are pre-applied in the glibc submodule.
# Patch order: glibc-2.40 -> nixpkgs patches -> Termux Android patches
# See submodules/glibc git log for patch details.
#
# Usage:
#   (import ./android-glibc.nix { glibcSrc = ./submodules/glibc; }) pkgs pkgs
{ glibcSrc }: final: prev: let
  # Only apply for aarch64-linux (Android)
  isAndroid = (final.stdenv.hostPlatform.system or final.system) == "aarch64-linux";

  # Path to build-time scripts (gen-android-ids.sh, process-fakesyscalls.sh, fakesyscall.json)
  termuxScripts = ./glibc-termux;

  # nix-on-droid paths from centralized config
  androidPaths = import ../modules/android/paths.nix;
  nixOnDroidPrefix = androidPaths.installationDir;
  nixOnDroidPrefixClassical = androidPaths.termuxBase;

  lib = final.lib;

  # Use final stdenv and pkgsBuildBuild to avoid bootstrap stages entirely
  # This builds Android glibc with the final compiler instead of bootstrap-stage2-stdenv
  glibcWithFinalStdenv = prev.glibc.override {
    stdenv = final.stdenv;
    # Use final packages for build-time dependencies instead of bootstrap
    pkgsBuildBuild = final.pkgsBuildBuild;
  };

in {
  glibc = if isAndroid then
    glibcWithFinalStdenv.overrideAttrs (oldAttrs: {
      # Use same-length name for patchnar compatibility (13 chars like "glibc-2.40-66")
      # "a1" = android version 1
      version = "2.40-a1";

      # Use patched glibc source from submodule
      # Both nixpkgs and Termux patches are pre-applied as git commits
      src = glibcSrc;

      # Use standard multi-output build (out, bin, dev, static, getent)
      # Now works because we use final.stdenv instead of bootstrap
      # outputs inherited from upstream glibc

      # Override depsBuildBuild to use final gcc instead of bootstrap
      depsBuildBuild = [ final.stdenv.cc ];

      # Skip nixpkgs patches - our source from submodule already has them pre-applied
      patches = [];

      # Replace nativeBuildInputs to use Android-patched tools
      # The original uses python3-minimal which hits seccomp issues on Android
      nativeBuildInputs = [
        final.bison
        final.python3
        final.jq
      ];

      # Don't set LD_PRELOAD - rely on /etc/ld.so.preload from nix-on-droid
      # which loads libfakechroot with SIGSYS handler for seccomp-blocked syscalls

      # Post-patch phase: run nixpkgs postPatch first, then Android-specific processing
      postPatch = (oldAttrs.postPatch or "") + ''
        echo "=== Applying nix-on-droid Android build-time processing ==="

        # Step 1: Remove clone3.S files (Android doesn't support clone3)
        find . -name "clone3.S" -type f -delete
        echo "Removed clone3.S files"

        # Step 2: Remove x86_64 configure scripts
        rm -f sysdeps/unix/sysv/linux/x86_64/configure* || true
        echo "Removed x86_64 configure scripts"

        # Step 3: Generate android_ids.h (needs runtime path substitution)
        bash ${termuxScripts}/gen-android-ids.sh ${nixOnDroidPrefixClassical} \
          nss/android_ids.h \
          nss/android_system_user_ids.h || echo "Warning: gen-android-ids.sh failed"
        echo "Generated android_ids.h"

        # Step 4: Process fakesyscall.json to generate disabled-syscall.h
        bash ${termuxScripts}/process-fakesyscalls.sh . ${termuxScripts} aarch64 || \
          echo "Warning: fakesyscalls processing failed"
        echo "Processed fakesyscalls"

        # Step 5: Replace /dev/* paths with /proc/self/fd/*
        sed -i 's|/dev/stderr|/proc/self/fd/2|g' $(grep -rl "/dev/stderr" . --include="*.c" --include="*.h" 2>/dev/null) 2>/dev/null || true
        sed -i 's|/dev/stdin|/proc/self/fd/0|g' $(grep -rl "/dev/stdin" . --include="*.c" --include="*.h" 2>/dev/null) 2>/dev/null || true
        sed -i 's|/dev/stdout|/proc/self/fd/1|g' $(grep -rl "/dev/stdout" . --include="*.c" --include="*.h" 2>/dev/null) 2>/dev/null || true
        echo "Replaced /dev/* paths with /proc/self/fd/*"

        echo "=== Android build-time processing complete ==="
      '';
      
      # Patch upstream postInstall to fix glob issue
      # Upstream uses "../glibc-2*/localedata/SUPPORTED" which fails with multiple matches
      # Replace with "$sourceRoot" which is the actual source directory variable
      postInstall = builtins.replaceStrings
        ["../glibc-2*/localedata/SUPPORTED"]
        ["../$sourceRoot/localedata/SUPPORTED"]
        (oldAttrs.postInstall or "")
      + ''
        echo "=== Android glibc postInstall additions ==="

        # Fix cycle: $out/libexec/getconf/* symlinks point to $bin/bin/getconf
        # This creates out->bin reference, causing cycle with bin->out (libraries)
        # Solution: replace symlinks with copies of the actual binary
        if [ -d "$out/libexec/getconf" ]; then
          for link in $out/libexec/getconf/*; do
            if [ -L "$link" ]; then
              target=$(readlink -f "$link" 2>/dev/null || true)
              if [ -n "$target" ] && [ -f "$target" ]; then
                rm "$link"
                cp "$target" "$link"
              else
                # Broken symlink - just remove it
                rm -f "$link"
              fi
            fi
          done
        fi

        echo "=== Android glibc postInstall complete ==="
      '';
      
      # Configure flags for Android
      configureFlags = let
        oldFlags = if lib.isFunction (oldAttrs.configureFlags or [])
          then (oldAttrs.configureFlags {})
          else (oldAttrs.configureFlags or []);
      in oldFlags ++ [
        "--disable-nscd"
        "--disable-profile"
        "--disable-werror"
      ];
      
      # Add Android prefix to trusted directories so ld.so searches there
      makeFlags = (oldAttrs.makeFlags or []) ++ [
        "user-defined-trusted-dirs=${nixOnDroidPrefix}/nix/store"
        # slibdir commented out to avoid multi-output cycles
        # "slibdir=${nixOnDroidPrefix}${builtins.placeholder "out"}/lib"
      ];

      # Pass android glibc lib path to ld.so for standard glibc redirection
      # This enables ld.so to redirect binaries built against standard glibc
      # to use our android-patched glibc at runtime
      # Note: Use env.NIX_CFLAGS_COMPILE for newer nixpkgs compatibility
      env = (oldAttrs.env or {}) // {
        NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") +
          " -DANDROID_GLIBC_LIB=\"${nixOnDroidPrefix}${builtins.placeholder "out"}/lib\"";
      };

      # Enable separateDebugInfo for proper debug symbol handling
      separateDebugInfo = true;
    })
  else
    prev.glibc;

}
