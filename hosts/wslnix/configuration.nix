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
      outputs.nixosModules.wsl-base
      ./users.nix
    ];

  # Enable Tailscale in userspace networking mode (no kernel TUN, ideal for WSL).
  services.tailscale = {
    useRoutingFeatures = "client";
    interfaceName = "userspace-networking";
    port = 0;
    authKeyFile = tailscaleAuthKeyFile;
    extraUpFlags = [ "--ssh" "--operator=${username}" ];
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
