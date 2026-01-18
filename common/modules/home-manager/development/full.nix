# Full development environment (texlive + coq)
# Requires NUR, only for desktop hosts
{pkgs, ...}: {
  imports = [
    ./packages.nix
    ./coq.nix
  ];

  # Add texlive (can't build on Android due to faketime issues)
  home.packages = with pkgs; [
    texlive.combined.scheme-full
    python3Packages.pygments
  ];
}
