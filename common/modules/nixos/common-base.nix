{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
in {
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
    };
    channel.enable = false;
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  environment.systemPackages = lib.mkBefore (map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.vim
    pkgs.wget
    pkgs.jq
  ]);

  services.openssh = {
    enable = lib.mkDefault true;
    startWhenNeeded = lib.mkDefault false;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
    };
  };

  services.tailscale.enable = lib.mkDefault true;
}
