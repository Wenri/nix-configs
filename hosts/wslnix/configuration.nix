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
    }: {
    # You can import other NixOS modules here
    imports = [
      outputs.nixosModules.wsl-base
      ./users.nix
    ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
