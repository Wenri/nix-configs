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
}: let
  packages = import ../../common/packages.nix {inherit pkgs;};
in {
  # You can import other home-manager modules here
  imports = [
    # Import common base modules shared across configurations
    outputs.homeModules.core.default
  ];

  # Add Rust and Go toolchains (full development module has NUR deps)
  home.packages = packages.rustToolchain ++ packages.goToolchain;

  # nixpkgs config is inherited from system when using home-manager.useGlobalPkgs

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
  };

  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  # home.packages = with pkgs; [ steam ];

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "25.05";
}
