# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  username,
  ...
}: let
  tailscaleAuthKeyFile = ../../secrets/tailscale-auth.key;
in {
  # You can import other NixOS modules here
  imports = [
    # You can also split up your configuration and import pieces of it here:
    ./users.nix
  ];

  # Enable WSL
  wsl.enable = true;

  nixpkgs = {
    config.allowUnfree = true;
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
    };
    # Opinionated: disable channels
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  # Set hostname
  networking.hostName = hostname;

  # Enable OpenSSH and rely on NixOS' built-in socket activation support.
  services.openssh = {
    enable = true;
    startWhenNeeded = true;
  };

  # Override the socket to listen on a local UNIX domain socket instead of TCP port 22.
  systemd.sockets.sshd.socketConfig = {
    ListenStream = lib.mkForce [ "/run/sshd.sock" ];
    SocketMode = "0600";
  };

  # System packages
  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.vim
    pkgs.wget
    pkgs.jq
  ];

  # Enable Tailscale in userspace networking mode (no kernel TUN, ideal for WSL).
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    interfaceName = "userspace-networking";
    port = 0;
    authKeyFile = tailscaleAuthKeyFile;
    extraUpFlags = [ "--ssh" ];
    extraSetFlags = [ "--operator" username ];
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
