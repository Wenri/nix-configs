# Base program enables shared across all configurations
# These are simple program.*.enable settings used everywhere
# Note: On nix-on-droid, packages from programs.* are patched centrally
# by path.nix (via build.patchPackageForAndroidGlibc), NOT here.
{pkgs, ...}: {
  programs = {
    home-manager.enable = true;
    tmux.enable = true;
    # vim: use home.packages instead of programs.vim (no customizations needed)
  };
  
  home.packages = [pkgs.vim];
}
