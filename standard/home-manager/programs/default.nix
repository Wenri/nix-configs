{
  imports = [
    ./zsh.nix
    ./emacs.nix
    ./git.nix
  ];

  programs = {
    home-manager.enable = true;
    tmux.enable = true;
    vim.enable = true;
    thefuck.enable = true;
  };
}