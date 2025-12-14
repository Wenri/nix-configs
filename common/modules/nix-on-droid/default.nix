# Nix-on-droid modules exported via flake
{
  base = import ./base.nix;
  android-integration = import ./android-integration.nix;
  sshd = import ./sshd.nix;
  locale = import ./locale.nix;
  shizuku = import ./shizuku.nix;
  absolute-symlinks = import ./absolute-symlinks.nix;
}
