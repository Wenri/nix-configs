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
    outputs.nixOnDroidModules.shizuku
  ];

  # Use absolute store paths for symlinks (works outside proot)
  build.absoluteStorePrefix = "/data/data/com.termux.nix/files/usr";

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
