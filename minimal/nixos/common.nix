# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: let
  tailscaleAuthKeyFile = "/home/nixos/nix-configs/secrets/tailscale-auth.key";
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
  };

  systemd.services."tailscale-autoauth" = {
    description = "Automatically authenticate Tailscale using auth key file";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = tailscaleAuthKeyFile;
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail

      AUTH_FILE=${lib.escapeShellArg tailscaleAuthKeyFile}
      if [ ! -s "$AUTH_FILE" ]; then
        echo "Tailscale auth key file missing or empty: $AUTH_FILE" >&2
        exit 1
      fi

      backend_state="$(${pkgs.tailscale}/bin/tailscale status --peers=false --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.BackendState // ""')"
      if [ "$backend_state" = "Running" ] || [ "$backend_state" = "NeedsMachineAuth" ]; then
        exit 0
      fi

      ${pkgs.tailscale}/bin/tailscale up --auth-key "file:${tailscaleAuthKeyFile}"
    '';
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
