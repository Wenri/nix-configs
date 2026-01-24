# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, glibcSrc ? null, fakechrootSrc ? null, patchnarSrc ? null }:
let
  androidPaths = import ../modules/android/paths.nix;
  inherit (androidPaths) installationDir;

  # Build Android glibc from source (uses final stdenv, not bootstrap)
  androidGlibc = if glibcSrc != null then
    (import ./android-glibc.nix { inherit glibcSrc; } pkgs pkgs).glibc
  else null;

  # Build Android fakechroot if both sources provided
  androidFakechroot = if androidGlibc != null && fakechrootSrc != null then
    import ./android-fakechroot.nix {
      inherit (pkgs) stdenv patchelf fakechroot boost;
      inherit androidGlibc installationDir;
      src = fakechrootSrc;
    }
  else null;

  # patchnar - NAR stream patcher (includes patchelf)
  # installationDir is set at compile time for Android patching
  patchnar = pkgs.callPackage ./patchnar.nix { inherit patchnarSrc installationDir; };

  # rish - Shizuku shell for privileged Android commands
  rish = pkgs.callPackage ./rish.nix { inherit installationDir; };
in {
  # example = pkgs.callPackage ./example { };
  inherit patchnar rish;
}
// (if androidGlibc != null then { inherit androidGlibc; } else {})
// (if androidFakechroot != null then { inherit androidFakechroot; } else {})
