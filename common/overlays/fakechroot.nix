# Android-patched fakechroot with compile-time hardcoded configuration
# All paths are baked in at build time - no environment variable fallback
#
# Required parameters:
#   androidGlibc    - Android-patched glibc package
#   installationDir - Base installation directory (e.g., /data/data/com.termux.nix/files/usr)
#   excludePath     - Colon-separated paths to exclude from translation
#
# Note: --library-path and --preload are no longer passed to ld.so because:
#   - ld.so.preload handles libfakechroot preloading
#   - ld.so has built-in glibc path redirection (standard -> android glibc)
#   - ld.so has built-in /nix/store path translation
#
# Example usage:
#   androidFakechroot = import ./fakechroot.nix {
#     inherit (pkgs) stdenv fetchFromGitHub patchelf fakechroot;
#     androidGlibc = myAndroidGlibc;
#     installationDir = "/data/data/com.termux.nix/files/usr";
#     excludePath = "/data:/proc:/sys:/dev:/system:/apex:/vendor:/linkerconfig";
#     src = ./submodules/fakechroot;  # Local source
#   };
{
  stdenv,
  patchelf,
  fakechroot,
  androidGlibc,
  installationDir,
  excludePath ? "/data:/proc:/sys:/dev:/system:/apex:/vendor:/linkerconfig",
  src,
}: let
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

    # Pass Android paths as compile-time constants
    # Note: LIBRARY_PATH and PRELOAD removed - ld.so handles these now
    NIX_CFLAGS_COMPILE = builtins.concatStringsSep " " [
      (oldAttrs.NIX_CFLAGS_COMPILE or "")
      ''-DANDROID_ELFLOADER="\"${androidLdso}\""''
      ''-DANDROID_BASE="\"${installationDir}\""''
      ''-DANDROID_EXCLUDE_PATH="\"${excludePath}\""''
    ];

    # Patch RPATH and interpreter for Android glibc
    postFixup =
      (oldAttrs.postFixup or "")
      + ''
        echo "=== Patching fakechroot for Android glibc ==="
        for lib in $out/lib/fakechroot/libfakechroot.so; do
          if [ -f "$lib" ]; then
            patchelf --set-rpath "${androidGlibcAbs}" "$lib" || true
            echo "  Patched RPATH: $lib"
          fi
        done
        for bin in $out/bin/fakechroot $out/bin/ldd.fakechroot; do
          if [ -f "$bin" ] && patchelf --print-interpreter "$bin" 2>/dev/null | grep -q ld-linux; then
            patchelf --set-interpreter "${androidLdso}" --set-rpath "${androidGlibcAbs}" "$bin" 2>/dev/null || true
            echo "  Patched: $bin"
          fi
        done
      '';
  })
