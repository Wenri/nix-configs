# glibc overlay for Android (nix-on-droid)
# Applies Termux patches incrementally for Android kernel compatibility
# Based on: https://github.com/termux-pacman/glibc-packages/tree/main/gpkg/glibc
final: prev: let
  # Only apply this overlay for aarch64-linux (Android)
  isAndroid = (final.stdenv.hostPlatform.system or final.system) == "aarch64-linux";

  # Path to Termux patches and source files
  termuxPatches = ./patches/glibc-termux;

  # nix-on-droid paths
  nixOnDroidPrefix = "/data/data/com.termux.nix/files/usr";
  nixOnDroidPrefixClassical = "/data/data/com.termux.nix/files";

  lib = final.lib;
in {
  glibc = if isAndroid then
    prev.glibc.overrideAttrs (oldAttrs: {
      # Force a new derivation name to avoid stale builds
      pname = "glibc-android";
      
      # Start with minimal patches - add more incrementally
      # Phase 1: disable-clone3 patch (essential for Android)
      patches = (oldAttrs.patches or []) ++ [
        (termuxPatches + "/disable-clone3.patch")
      ];
      
      # Post-patch phase: apply Termux pre-configure modifications
      postPatch = (oldAttrs.postPatch or "") + ''
        echo "=== Applying nix-on-droid Android modifications ==="
        
        # Step 1: Remove clone3.S files (Termux: rm clone3.S)
        find . -name "clone3.S" -type f -delete
        echo "✓ Removed clone3.S files"

        # Step 2: Remove x86_64 configure scripts (Termux: rm configure*)
        rm -f sysdeps/unix/sysv/linux/x86_64/configure* || true
        echo "✓ Removed x86_64 configure scripts"
        
        echo "=== Phase 1 modifications complete ==="
      '';
      
      # Fix broken symlinks in getconf - these point to 32-bit getconf variants
      # which don't exist on aarch64-only builds. Remove them in postInstall.
      postInstall = (oldAttrs.postInstall or "") + ''
        echo "=== Fixing broken getconf symlinks ==="
        # Remove broken symlinks that point to non-existent 32-bit variants
        find $out -xtype l -name "*LP64*" -delete 2>/dev/null || true
        find $out -xtype l -name "*XBS5*" -delete 2>/dev/null || true
        echo "✓ Removed broken LP64/XBS5 symlinks"
      '';
      
      # Minimal configure flags
      configureFlags = let
        oldFlags = if lib.isFunction (oldAttrs.configureFlags or [])
          then (oldAttrs.configureFlags {})
          else (oldAttrs.configureFlags or []);
      in oldFlags ++ [
        "--disable-werror"
      ];
    })
  else
    prev.glibc;
}
