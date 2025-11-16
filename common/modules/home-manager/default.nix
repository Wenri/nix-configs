# Exportable home-manager modules
# All users (wenri, nixos, xsnow) are the same person: Bingchen Gong
#
# Usage in home.nix:
#   imports = [
#     outputs.homeManagerModules.base              # Core modules (git, zsh, ssh, etc.)
#     outputs.homeManagerModules.desktop-packages  # GUI applications (optional)
#     outputs.homeManagerModules.development       # Dev environments (optional)
#     outputs.homeManagerModules.programs          # Desktop programs (optional)
#   ];
{
  # Core base configuration - includes base-packages, git, zsh, ssh, gh, programs
  base = import ./base.nix;

  # Optional modules
  desktop-packages = import ./desktop-packages.nix;
  development = import ./development;
  programs = import ./programs;

  # Individual base components (if you want granular control)
  base-packages = import ./base-packages.nix;
  git = import ./git.nix;
  zsh = import ./zsh.nix;
  ssh = import ./ssh.nix;
  gh = import ./gh.nix;
  programs-base = import ./programs.nix;
}
