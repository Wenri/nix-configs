# Android/nix-on-droid modules exported via flake
{
  # Shared path constants (not a module, just an attribute set)
  paths = import ./paths.nix;

  # NixOS-style modules
  base = import ./base.nix;
  android-integration = import ./android-integration.nix;
  sshd = import ./sshd.nix;
  locale = import ./locale.nix;
  shizuku = import ./shizuku.nix;
}
