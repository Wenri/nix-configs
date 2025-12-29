# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, android ? null }:
{
  # example = pkgs.callPackage ./example { };
}
// (if android != null then {
  # Android packages (available on all systems, built for aarch64-linux)
  androidGlibc = android.glibc;
  androidFakechroot = android.fakechroot;
} else {})
