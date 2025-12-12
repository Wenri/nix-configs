# glibc overlay for Android (nix-on-droid)
# Currently disabled - using standard nixpkgs glibc for compatibility
# TODO: Apply Termux patches once version compatibility is resolved
final: prev: let
  isAndroid = (final.stdenv.hostPlatform.system or final.system) == "aarch64-linux";
in {
  # For now, just return unmodified glibc
  # The patchelf approach will use this standard glibc which is sufficient for most use cases
  glibc = prev.glibc;
}
