# Android-patched fakechroot with compile-time hardcoded configuration
# All paths are baked in at build time - no environment variable fallback
#
# Required parameters:
#   androidGlibc    - Android-patched glibc package
#   installationDir - Base installation directory (e.g., /data/data/com.termux.nix/files/usr)
#   src             - Path to fakechroot source
#
# Note: --library-path and --preload are no longer passed to ld.so because:
#   - ld.so.preload handles libfakechroot preloading
#   - ld.so has built-in glibc path redirection (standard -> android glibc)
#   - ld.so has built-in /nix/store path translation
#
# Example usage:
#   androidFakechroot = import ./android-fakechroot.nix {
#     inherit (pkgs) stdenv patchelf fakechroot;
#     androidGlibc = myAndroidGlibc;
#     installationDir = "/data/data/com.termux.nix/files/usr";
#     src = ./submodules/fakechroot;
#   };
{
  stdenv,
  patchelf,
  fakechroot,
  androidGlibc,
  installationDir,
  src,
}: let
  # Android system paths excluded from chroot translation
  excludePath = "/3rdmodem:/acct:/apex:/android:/bugreports:/cache:/config:/d:/data:/data_mirror:/debug_ramdisk:/dev:/linkerconfig:/log:/metadata:/mnt:/odm:/odm_dlkm:/oem:/proc:/product:/sdcard:/storage:/sys:/system:/system_ext:/vendor:/vendor_dlkm";
  # Compute absolute paths with Android prefix
  androidGlibcAbs = "${installationDir}${androidGlibc}/lib";
  androidLdso = "${androidGlibcAbs}/ld-linux-aarch64.so.1";
in
  fakechroot.overrideAttrs (oldAttrs: {
    pname = "fakechroot-android";
    version = "unstable-local";
    inherit src;
    patches = [];

    nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [patchelf];

    # Pass Android paths to configure via AC_ARG_VAR environment variables
    # These get written to config.h via AC_DEFINE_UNQUOTED
    ANDROID_ELFLOADER = androidLdso;
    ANDROID_BASE = installationDir;
    ANDROID_EXCLUDE_PATH = excludePath;

    # Patch interpreter and RPATH for Android glibc
    # IMPORTANT: libfakechroot.so MUST have RPATH set to Android glibc!
    # Without this, libfakechroot.so resolves glibc functions (like posix_spawn)
    # from standard glibc, which uses clone3 syscall blocked by Android seccomp.
    postFixup =
      (oldAttrs.postFixup or "")
      + ''
        echo "=== Patching fakechroot for Android glibc ==="

        # Patch binaries
        for bin in $out/bin/fakechroot $out/bin/ldd.fakechroot; do
          if [ -f "$bin" ] && patchelf --print-interpreter "$bin" 2>/dev/null | grep -q ld-linux; then
            patchelf --set-interpreter "${androidLdso}" --set-rpath "${androidGlibcAbs}" "$bin" 2>/dev/null || true
            echo "  Patched binary: $bin"
          fi
        done

        # CRITICAL: Patch libfakechroot.so RPATH to use Android glibc
        # This ensures all glibc function calls (posix_spawn, etc.) use Android glibc
        # which avoids clone3 and other blocked syscalls
        LIBFAKE="$out/lib/fakechroot/libfakechroot.so"
        if [ -f "$LIBFAKE" ]; then
          OLD_RPATH=$(patchelf --print-rpath "$LIBFAKE" 2>/dev/null || echo "")
          echo "  libfakechroot.so old RPATH: $OLD_RPATH"

          # Prepend Android glibc path to RPATH (so it's searched first)
          if [ -n "$OLD_RPATH" ]; then
            NEW_RPATH="${androidGlibcAbs}:$OLD_RPATH"
          else
            NEW_RPATH="${androidGlibcAbs}"
          fi

          patchelf --set-rpath "$NEW_RPATH" "$LIBFAKE" 2>/dev/null || true
          echo "  libfakechroot.so new RPATH: $NEW_RPATH"
          echo "  Patched library: $LIBFAKE"
        fi

        echo "=== Fakechroot patching complete ==="
      '';
  })
