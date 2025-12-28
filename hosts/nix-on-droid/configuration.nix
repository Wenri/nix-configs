# Nix-on-droid configuration for Android
# Uses modular configuration from common/modules/android/
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
    outputs.androidModules.base
    outputs.androidModules.android-integration
    outputs.androidModules.sshd
    outputs.androidModules.locale
    outputs.androidModules.shizuku
  ];

  # Enable Android/Termux integration tools
  android.termuxTools = true;

  # Enable SSH server
  services.sshd.enable = true;

  # Enable Shizuku rish shell
  programs.shizuku.enable = true;

  # Configure home-manager
  home-manager = {
    config = ./home.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;  # Reverted: nix-on-droid merges home-manager packages into system environment regardless
    extraSpecialArgs = config._module.specialArgs;  # Pass all specialArgs including patchPackageForAndroidGlibc
  };
}
