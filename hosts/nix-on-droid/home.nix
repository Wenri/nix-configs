{
  lib,
  pkgs,
  sshd-start, # Passed from configuration.nix via extraSpecialArgs
  ...
}: let
  keys = import ../../common/keys.nix;
in {
  # Import shared core modules
  imports = [
    ../../common/modules/home-manager/core
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # Declarative SSH authorized_keys and termux-boot
  # Note: sshd_config is embedded directly in the start script (Nix store)
  home.file = {
    ".ssh/authorized_keys".text = lib.concatStringsSep "\n" keys.all;
    ".termux/boot/start-sshd".source = sshd-start;
  };

  # nix-on-droid specific shell aliases
  programs.zsh.shellAliases = {
    update = "nix-on-droid switch --flake ~/.config/nix-on-droid";
    sshd-start = "~/.termux/boot/start-sshd";
    sshd-stop = "pkill -f 'sshd -f'";
  };
}
