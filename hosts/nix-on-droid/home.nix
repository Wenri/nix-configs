# Home-manager configuration for nix-on-droid
# Minimal host-specific config - shared modules provide most functionality
{
  lib,
  pkgs,
  outputs,
  hostname,
  username,
  sshd-start ? null,
  sshdAuthorizedKeys ? [],
  ...
}: let
  keys = import ../../common/keys.nix;
in {
  # Import shared core modules
  imports = [
    outputs.homeModules.core.default
  ];

  # Home Manager release compatibility
  home.stateVersion = "24.05";

  # Declarative SSH authorized_keys and termux-boot
  home.file = lib.mkMerge [
    {
      ".ssh/authorized_keys".text = lib.concatStringsSep "\n" (
        if sshdAuthorizedKeys != []
        then sshdAuthorizedKeys
        else keys.all
      );
    }
    (lib.mkIf (sshd-start != null) {
      ".termux/boot/start-sshd".source = sshd-start;
    })
  ];

  # nix-on-droid specific shell aliases
  programs.zsh.shellAliases = {
    update = "nix-on-droid switch --flake ~/.config/nix-on-droid";
    sshd-start = "~/.termux/boot/start-sshd";
    sshd-stop = "pkill -f 'sshd -f'";
  };
}
