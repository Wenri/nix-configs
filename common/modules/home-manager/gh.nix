# GitHub CLI configuration for all environments
# Authentication is done via: gh auth login
{pkgs, ...}: {
  programs.gh = {
    enable = true;

    # Enable gh as git credential helper for GitHub
    gitCredentialHelper.enable = true;

    settings = {
      # Default settings for gh CLI
      # git_protocol = "ssh";
      # editor = "vim";
    };
  };
}
