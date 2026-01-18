# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  username,
  hostname,
  ...
}: {
  # You can import other home-manager modules here
    imports = [
      # Import common base modules shared across configurations
      outputs.homeModules.core.default

      # Import desktop and development modules from common
      outputs.homeModules.desktop.default
      outputs.homeModules.development.full

      # Or modules exported from other flakes (such as nix-colors):
      # inputs.nix-colors.homeModules.default

      # You can also split up your configuration and import pieces of it here:
      # ./nvim.nix
    ];

  # When using home-manager.useGlobalPkgs, nixpkgs config and overlays are inherited from system
  # Overlays should be configured at the NixOS level, not here

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # home.packages = with pkgs; [ steam ];

  # Enable home-manager
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "25.05";
}
