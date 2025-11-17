# Exportable home-manager modules
# All users (wenri, nixos, xsnow) are the same person: Bingchen Gong
#
# Usage in home.nix:
#   imports = [
#     outputs.homeModules.core.default        # Core modules (git, zsh, ssh, etc.)
#     outputs.homeModules.desktop.default     # Desktop packages + program configs
#     outputs.homeModules.development         # Dev environments (optional)
#   ];
{
  core = {
    default = import ./core;
    packages = import ./core/packages.nix;
    programs = import ./core/programs.nix;
    git = import ./core/git.nix;
    zsh = import ./core/zsh.nix;
    ssh = import ./core/ssh.nix;
    gh = import ./core/gh.nix;
  };

  desktop = {
    default = import ./desktop/default.nix;
    packages = import ./desktop/packages.nix;
  };

  development = import ./development;
}
