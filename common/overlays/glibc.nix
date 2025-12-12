# glibc overlay for Android (nix-on-droid)
# Applies Termux patches for Android kernel compatibility
# Based on: https://github.com/termux-pacman/glibc-packages/tree/main/gpkg/glibc
final: prev: let
  # Only apply this overlay for aarch64-linux (Android)
  isAndroid = (final.stdenv.hostPlatform.system or final.system) == "aarch64-linux";

  # Path to Termux patches and source files
  termuxPatches = ./patches/glibc-termux;

  # nix-on-droid paths (equivalent to Termux's prefix paths)
  nixOnDroidPrefix = "/data/data/com.termux.nix/files/usr";
  nixOnDroidPrefixClassical = "/data/data/com.termux.nix/files";

  lib = final.lib;
  
  # All Termux patches for glibc 2.40 (adapted from 2.41)
  # Order matters - some patches depend on changes from earlier patches
  allPatches = [
    # Essential: disable clone3 which Android kernel doesn't support
    "disable-clone3.patch"
    # Kernel feature flags for Android
    "kernel-features.h.patch"
    # Makefile modifications for Android-specific files
    "misc-Makefile.patch"
    "misc-Versions.patch"
    "nss-Makefile.patch"
    "posix-Makefile.patch"
    "sysvipc-Makefile.patch"
    # Code patches for Android compatibility
    "clock_gettime.c.patch"
    "dl-execstack.c.patch"
    "faccessat.c.patch"
    "fchmodat.c.patch"
    "fstatat64.c.patch"
    "getXXbyYY.c.patch"
    "getXXbyYY_r.c.patch"
    "getgrgid.c.patch"
    "getgrnam.c.patch"
    "getpwnam.c.patch"
    "getpwuid.c.patch"
    "sem_open.c.patch"
    "tcsetattr.c.patch"
    "unistd.h.patch"
    # Large patches: path replacements, syscall wrappers, etc.
    "set-dirs.patch"          # Path replacements for Android
    "set-fakesyscalls.patch"  # Fake syscall implementations
    "set-ld-variables.patch"  # LD environment variables
    "set-nptl-syscalls.patch" # Disable blocked NPTL syscalls (adapted for 2.40)
    "set-sigrestore.patch"    # Signal restore handling
    "set-static-stubs.patch"  # Static linking stubs
    "syscall.S.patch"         # Assembly syscall wrapper
  ];

in {
  glibc = if isAndroid then
    prev.glibc.overrideAttrs (oldAttrs: {
      # Force a new derivation name to track Android-specific builds
      pname = "glibc-android";
      
      # Apply all Termux patches
      patches = (oldAttrs.patches or []) ++ (map (p: termuxPatches + "/${p}") allPatches);
      
      # Add jq for processing fakesyscall.json
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ final.jq ];
      
      # Post-patch phase: apply Termux pre-configure modifications
      # These are file copies and in-place edits that aren't done via patches
      postPatch = (oldAttrs.postPatch or "") + ''
        echo "=== Applying nix-on-droid Android modifications ==="
        
        # Step 1: Remove clone3.S files (Android doesn't support clone3)
        find . -name "clone3.S" -type f -delete
        echo "✓ Removed clone3.S files"

        # Step 2: Remove x86_64 configure scripts
        rm -f sysdeps/unix/sysv/linux/x86_64/configure* || true
        echo "✓ Removed x86_64 configure scripts"

        # Step 3: Install syscall wrapper files
        for f in shmat.c shmctl.c shmdt.c shmget.c mprotect.c syscall.c \
                 fakesyscall-base.h fakesyscall.h fake_epoll_pwait2.c \
                 setfsuid.c setfsgid.c; do
          if [ -f "${termuxPatches}/$f" ]; then
            cp "${termuxPatches}/$f" sysdeps/unix/sysv/linux/
            echo "  ✓ Copied: $f -> sysdeps/unix/sysv/linux/"
          fi
        done

        # Step 4: Install Android passwd/group handling
        for f in android_passwd_group.c android_passwd_group.h android_system_user_ids.h; do
          if [ -f "${termuxPatches}/$f" ]; then
            cp "${termuxPatches}/$f" nss/
            echo "  ✓ Copied: $f -> nss/"
          fi
        done

        # Step 5: Generate android_ids.h
        if [ -f "${termuxPatches}/gen-android-ids.sh" ]; then
          bash ${termuxPatches}/gen-android-ids.sh ${nixOnDroidPrefixClassical} \
            nss/android_ids.h \
            ${termuxPatches}/android_system_user_ids.h || echo "Warning: gen-android-ids.sh failed (non-fatal)"
          echo "✓ Generated android_ids.h"
        fi

        # Step 6: Install Android syslog
        if [ -f "${termuxPatches}/syslog.c" ]; then
          cp ${termuxPatches}/syslog.c misc/
          echo "✓ Installed Android syslog"
        fi

        # Step 7: Install shmem-android (System V shared memory emulation)
        for f in shmem-android.c shmem-android.h; do
          if [ -f "${termuxPatches}/$f" ]; then
            cp "${termuxPatches}/$f" sysvipc/
            echo "  ✓ Copied: $f -> sysvipc/"
          fi
        done

        # Step 8: Install SDT (SystemTap) stub headers
        mkdir -p include/sys
        for f in sdt.h sdt-config.h; do
          if [ -f "${termuxPatches}/$f" ]; then
            cp "${termuxPatches}/$f" include/sys/
            echo "  ✓ Copied: $f -> include/sys/"
          fi
        done

        # Step 9: Process fakesyscall.json to generate disabled-syscall.h
        if [ -f "${termuxPatches}/process-fakesyscalls.sh" ]; then
          bash ${termuxPatches}/process-fakesyscalls.sh . ${termuxPatches} aarch64 || \
            echo "Warning: fakesyscalls processing failed (non-fatal)"
          echo "✓ Processed fakesyscalls"
        fi

        # Step 10: Replace /dev/* paths with /proc/self/fd/*
        for replacement in /dev/stderr:/proc/self/fd/2 \
                          /dev/stdin:/proc/self/fd/0 \
                          /dev/stdout:/proc/self/fd/1; do
          old_path="''${replacement%%:*}"
          new_path="''${replacement##*:}"
          find . -type f \( -name "*.c" -o -name "*.h" \) -exec grep -l "$old_path" {} + 2>/dev/null | \
            xargs -r sed -i "s|$old_path|$new_path|g" || true
        done
        echo "✓ Replaced /dev/* paths with /proc/self/fd/*"
        
        echo "=== Android modifications complete ==="
      '';
      
      # Fix broken symlinks and cross-output references
      postInstall = (oldAttrs.postInstall or "") + ''
        echo "=== Fixing broken getconf symlinks ==="
        find $out -xtype l -name "*LP64*" -delete 2>/dev/null || true
        find $out -xtype l -name "*XBS5*" -delete 2>/dev/null || true
        echo "✓ Removed broken LP64/XBS5 symlinks"
        
        # Fix cross-output symlinks in libexec/getconf that create cycles
        # These symlinks point from out/libexec/getconf/* to bin/bin/getconf
        # Replace them with copies to break the cycle
        echo "=== Fixing getconf cross-output references ==="
        if [ -d "$out/libexec/getconf" ]; then
          for link in $out/libexec/getconf/*; do
            if [ -L "$link" ]; then
              target=$(readlink -f "$link")
              if [ -f "$target" ]; then
                rm "$link"
                cp "$target" "$link"
                echo "  ✓ Converted symlink to copy: $(basename $link)"
              fi
            fi
          done
        fi
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
      
      # Disable separateDebugInfo to avoid output cycles
      separateDebugInfo = false;
    })
  else
    prev.glibc;

  # Helper function to replace glibc in a package using patchelf
  # This allows using binary-cached packages with our Android glibc
  patchGlibcFor = androidGlibc: pkg: pkg.overrideAttrs (oldAttrs: {
    postFixup = (oldAttrs.postFixup or "") + ''
      echo "=== Patching glibc references for Android ==="
      for f in $(find $out -type f -executable 2>/dev/null); do
        if ${final.patchelf}/bin/patchelf --print-interpreter "$f" 2>/dev/null | grep -q ld-linux; then
          echo "  Patching: $f"
          ${final.patchelf}/bin/patchelf \
            --set-interpreter ${androidGlibc}/lib/ld-linux-aarch64.so.1 \
            --set-rpath ${androidGlibc}/lib:$(${final.patchelf}/bin/patchelf --print-rpath "$f" 2>/dev/null || echo "") \
            "$f" 2>/dev/null || true
        fi
      done
      echo "=== Done patching ==="
    '';
  });
}
