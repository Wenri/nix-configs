{
  imports = [
    ./zsh.nix
    ./git.nix
    ./ssh.nix
  ];

  programs = {
    home-manager.enable = true;
    tmux.enable = true;
    vim.enable = true;
    thefuck.enable = true;
  };
}
