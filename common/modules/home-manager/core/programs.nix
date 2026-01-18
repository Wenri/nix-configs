# Base program enables shared across all configurations
# These are simple program.*.enable settings used everywhere
# Note: On nix-on-droid, packages from programs.* are patched centrally
# by path.nix (via build.replaceAndroidDependencies), NOT here.
{
  programs = {
    home-manager.enable = true;
    tmux.enable = true;

    # Fuzzy finder with shell integration
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
