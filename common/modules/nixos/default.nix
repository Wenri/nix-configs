# Add your reusable NixOS modules to this directory, on their own file (https://nixos.wiki/wiki/Module).
# These should be stuff you would like to share with others, not your personal configurations.
{
  # List your module files here
  common-base = import ./common-base.nix;
  server-base = import ./server-base.nix;
  users = import ./users.nix;
  locale = import ./locale.nix;
  secrets = import ./secrets.nix;
  tailscale = import ./tailscale.nix;
  disk-config = import ./disk-config.nix;
  desktop-base = import ./desktop-base.nix;
  wsl-base = import ./wsl-base.nix;
}
