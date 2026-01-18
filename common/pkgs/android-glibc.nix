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

in {
  glibc = if isAndroid then
    prev.glibc.overrideAttrs (oldAttrs: {
      # Force a new derivation name to track Android-specific builds
      pname = "glibc-android";

      # Use patched glibc source from submodule
      # Both nixpkgs and Termux patches are pre-applied as git commits
      src = glibcSrc;
      version = "2.40-android";

      # Force single output to work around multi-output build issues on Android
      # The bootstrap tools crash when building multi-output derivations
      outputs = [ "out" ];

      # Skip nixpkgs patches - our source from submodule already has them pre-applied
      patches = [];

      # Add jq for processing fakesyscall.json
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ final.jq ];

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
      
      # Replace postInstall - simplified for single-output build
      # (nixpkgs version has glob issues and multi-output handling we don't need)
      postInstall = ''
        echo "=== Android glibc postInstall ==="

        # Fix the glob issue - find the actual source directory
        GLIBC_SRC=$(find .. -maxdepth 1 -type d -name 'glibc-*' | head -1)
        if [ -n "$GLIBC_SRC" ] && [ -d "$GLIBC_SRC/localedata" ]; then
          echo SUPPORTED-LOCALES=C.UTF-8/UTF-8 > "$GLIBC_SRC/localedata/SUPPORTED"
        fi

        # Build locales
        make -j''${NIX_BUILD_CORES:-1} localedata/install-locale-files || true

        test -f $out/etc/ld.so.cache && rm $out/etc/ld.so.cache

        # Link linux headers to include directory
        if test -n "$linuxHeaders"; then
            mkdir -p $out/include
            (cd $out/include && \
             ln -sv $(ls -d $linuxHeaders/include/* | grep -v scsi\$) .)
        fi

        # Fix for NIXOS-54 (ldd not working on x86_64)
        if test -n "$is64bit"; then
            ln -s lib $out/lib64
        fi

        rm -rf $out/var
        rm -f $out/bin/sln 2>/dev/null || true

        # Backwards-compatibility symlinks
        ln -sf $out/lib/libpthread.so.0 $out/lib/libpthread.so
        ln -sf $out/lib/librt.so.1 $out/lib/librt.so
        ln -sf $out/lib/libdl.so.2 $out/lib/libdl.so
        test -f $out/lib/libutil.so.1 && ln -sf $out/lib/libutil.so.1 $out/lib/libutil.so
        touch $out/lib/libpthread.a

        # Keep static libraries in $out/lib (single output)
        # No need to move to separate $static output

        # Work around Nix hard link bug for getconf
        if [ -f "$out/bin/getconf" ]; then
          cp $out/bin/getconf $out/bin/getconf_
          mv $out/bin/getconf_ $out/bin/getconf
        fi

        # Android-specific fixes
        echo "Fixing broken getconf symlinks..."
        find $out -xtype l -name "*LP64*" -delete 2>/dev/null || true
        find $out -xtype l -name "*XBS5*" -delete 2>/dev/null || true

        if [ -d "$out/libexec/getconf" ]; then
          for link in $out/libexec/getconf/*; do
            if [ -L "$link" ]; then
              target=$(readlink -f "$link" 2>/dev/null || true)
              if [ -n "$target" ] && [ -f "$target" ]; then
                rm "$link"
                cp "$target" "$link"
              fi
            fi
          done
        fi

        find "$out" -type d -empty -delete 2>/dev/null || true

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
        # Set slibdir to Android path so library paths are baked correctly
        "slibdir=${nixOnDroidPrefix}${builtins.placeholder "out"}/lib"
      ];

      # Pass android glibc lib path to ld.so for standard glibc redirection
      # This enables ld.so to redirect binaries built against standard glibc
      # to use our android-patched glibc at runtime
      # Note: Use env.NIX_CFLAGS_COMPILE for newer nixpkgs compatibility
      env = (oldAttrs.env or {}) // {
        NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") +
          " -DANDROID_GLIBC_LIB=\"${nixOnDroidPrefix}${builtins.placeholder "out"}/lib\"";
      };

      # Disable separateDebugInfo to avoid output cycles
      separateDebugInfo = false;
    })
  else
    prev.glibc;

}
