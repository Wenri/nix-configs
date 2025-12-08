# Nix-on-droid configuration for Android
# Uses modular configuration from common/modules/nix-on-droid/
{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  hostname,
  username,
  ...
}: {
  # Import shared modules
  imports = [
    outputs.nixOnDroidModules.base
    outputs.nixOnDroidModules.android-integration
    outputs.nixOnDroidModules.sshd
    outputs.nixOnDroidModules.locale
  ];

  # Enable Android/Termux integration tools
  android.termuxTools = true;

  # Enable SSH server
  services.sshd.enable = true;

  # Configure home-manager
  home-manager = {
    config = ./home.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
    extraSpecialArgs = {
      inherit outputs hostname username;
    };
  };
}
