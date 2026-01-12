{
  inputs,
  outputs,
  lib,
  pkgs,
  config,
  ...
}: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  packages = import ../../packages.nix {inherit pkgs;};
in {
  imports = [
    ./common-services.nix
  ];

  # System packages shared across NixOS hosts
  # Uses shared package lists from common/packages.nix
  environment.systemPackages = lib.mkBefore (map lib.lowPrio (
    packages.networkTools
    ++ packages.devTools
    ++ packages.nixosOnly
  ));

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
      outputs.overlays.master-packages
      inputs.nur.overlays.default
      inputs.nix-vscode-extensions.overlays.default
    ];
    config.allowUnfree = lib.mkDefault true;
  };

  nix = {
    settings = {
      experimental-features = "nix-command flakes";
      flake-registry = "";
      nix-path = config.nix.nixPath;
      # Use netrc for GitLab authentication (synced from glab via glab-netrc-sync)
      netrc-file = "/home/wenri/.netrc";
    };
    channel.enable = false;
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };
}
