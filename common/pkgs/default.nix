# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, glibcSrc ? null, fakechrootSrc ? null }:
let
  installationDir = "/data/data/com.termux.nix/files/usr";

  # Build Android glibc if source provided
  androidGlibc = if glibcSrc != null then
    (import ../overlays/glibc.nix { inherit glibcSrc; } pkgs pkgs).glibc
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
