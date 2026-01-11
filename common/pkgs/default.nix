# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, glibcSrc ? null, fakechrootSrc ? null }:
let
  installationDir = "/data/data/com.termux.nix/files/usr";

  # Use existing Android glibc from store if available, otherwise build
  # This is needed because bootstrap tools crash on Android (unpatched glibc)
  # and rebuilding glibc requires patched bootstrap tools
  existingGlibcPath = builtins.storePath /nix/store/6mjpqffiqrgqc80d3f54j5hxcj2dl0aj-glibc-android-2.40-android;

  # Build Android glibc if source provided
  androidGlibc = if glibcSrc != null then
    # Try using existing glibc if it exists, otherwise build from source
    if builtins.pathExists existingGlibcPath
    then existingGlibcPath
    else (import ../overlays/glibc.nix { inherit glibcSrc; } pkgs pkgs).glibc
  else null;

  # Build Android fakechroot if both sources provided
  androidFakechroot = if androidGlibc != null && fakechrootSrc != null then
    import ./android-fakechroot.nix {
      inherit (pkgs) stdenv patchelf fakechroot;
      inherit androidGlibc installationDir;
      src = fakechrootSrc;
    }
  else null;
in {
  # example = pkgs.callPackage ./example { };
}
// (if androidGlibc != null then { inherit androidGlibc; } else {})
// (if androidFakechroot != null then { inherit androidFakechroot; } else {})
