{
  imports = [
    ./zsh.nix
    ./git.nix
  ];

  programs = {
    home-manager.enable = true;
    tmux.enable = true;
    vim.enable = true;
  };
}
