# Common home-manager modules shared across configurations
# Import this module to get base packages and program configurations
# All users (wenri, nixos, xsnow) are the same person: Bingchen Gong
#
# Optional modules (not imported by default):
#   - ./desktop-packages.nix - Desktop GUI applications
#   - ./development - Development environments (Coq, Haskell, LaTeX, etc.)
#   - ./programs - Desktop-specific programs (rime, vscode, emacs, firefox, gnome)
{
  imports = [
    ./base-packages.nix
    ./git.nix
    ./zsh.nix
    ./ssh.nix
    ./gh.nix
    ./programs.nix
  ];
}
