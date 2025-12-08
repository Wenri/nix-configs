{...}: {
  # Import shared core modules
  imports = [
    ../../common/modules/home-manager/core
  ];

  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # nix-on-droid specific shell aliases
  programs.zsh.shellAliases = {
    update = "nix-on-droid switch --flake ~/.config/nix-on-droid";
    sshd-start = "sshd -f ~/.ssh/sshd_config";
    sshd-stop = "pkill -f 'sshd -f'";
  };
}
