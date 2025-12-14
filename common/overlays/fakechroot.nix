# Fakechroot from Wenri's fork with elfloader audit/preload support
# Built against Android glibc for nix-on-droid compatibility
final: oldAttrs: let
  # Get Android glibc from flake outputs (must be passed via specialArgs or pkgs)
  androidGlibcLib = "/data/data/com.termux.nix/files/usr/nix/store/4c9dx2bn6wyjq5kz4x0smbfkvdr0c2qh-glibc-android-2.40-66/lib";
  isAndroid = (final.stdenv.hostPlatform.system or final.system) == "aarch64-linux";
in {
  version = "unstable-2024-12-14";
  src = final.fetchFromGitHub {
    owner = "Wenri";
    repo = "fakechroot";
    rev = "cfc132d8c9b6a2cd34a00292be5ce8c5d5fb25e4";
    hash = "sha256-ILcm0ZGkS46uIBr+aoAv3a5y9AGN9Y9/2HU7CsTL/gU=";
  };

  # No additional patches needed - our changes are in the fork
  patches = [];

  # Add patchelf for RUNPATH patching on Android
  nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ 
    (if isAndroid then [ final.patchelf ] else []);

  # Patch RUNPATH to use Android glibc on aarch64-linux
  postFixup = (oldAttrs.postFixup or "") + (if isAndroid then ''
    echo "=== Patching fakechroot for Android glibc ==="
    
    # Patch libfakechroot.so
    for lib in $out/lib/fakechroot/libfakechroot.so; do
      if [ -f "$lib" ]; then
        echo "  Patching RUNPATH: $lib"
        ${final.patchelf}/bin/patchelf --set-rpath "${androidGlibcLib}" "$lib" || true
      fi
    done
    
    # Patch the fakechroot binary if it exists
    for bin in $out/bin/fakechroot $out/bin/ldd.fakechroot; do
      if [ -f "$bin" ] && [ -x "$bin" ]; then
        if ${final.patchelf}/bin/patchelf --print-interpreter "$bin" 2>/dev/null | grep -q ld-linux; then
          echo "  Patching interpreter and RUNPATH: $bin"
          ${final.patchelf}/bin/patchelf \
            --set-interpreter "${androidGlibcLib}/ld-linux-aarch64.so.1" \
            --set-rpath "${androidGlibcLib}" \
            "$bin" 2>/dev/null || true
        fi
      fi
    done
    
    echo "=== Fakechroot Android patching complete ==="
  '' else "");
}
