# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, glibcSrc ? null, fakechrootSrc ? null, patchnarSrc ? null }:
let
  androidPaths = import ../android-paths.nix;
  inherit (androidPaths) installationDir;

  # Use existing Android glibc from store if available, otherwise build
  # This is needed because bootstrap tools crash on Android (unpatched glibc)
  # and rebuilding glibc requires patched bootstrap tools
  existingGlibcStorePath = /nix/store/6mjpqffiqrgqc80d3f54j5hxcj2dl0aj-glibc-android-2.40-android;

  # Build Android glibc if source provided
  androidGlibc = if glibcSrc != null then
    # Try using existing glibc if it exists, otherwise build from source
    if builtins.pathExists existingGlibcStorePath
    then builtins.storePath existingGlibcStorePath
    else (import ./android-glibc.nix { inherit glibcSrc; } pkgs pkgs).glibc
  else null;

  # Build Android fakechroot if both sources provided
  androidFakechroot = if androidGlibc != null && fakechrootSrc != null then
    import ./android-fakechroot.nix {
      inherit (pkgs) stdenv patchelf fakechroot;
      inherit androidGlibc installationDir;
      src = fakechrootSrc;
    }
  else null;

  # patchnar - NAR stream patcher (includes patchelf)
  patchnar = pkgs.callPackage ./patchnar.nix { inherit patchnarSrc; };

  # rish - Shizuku shell for privileged Android commands
  rish = pkgs.callPackage ./rish.nix { inherit installationDir; };
in {
  # example = pkgs.callPackage ./example { };
  inherit patchnar rish;
}
// (if androidGlibc != null then { inherit androidGlibc; } else {})
// (if androidFakechroot != null then { inherit androidFakechroot; } else {})
