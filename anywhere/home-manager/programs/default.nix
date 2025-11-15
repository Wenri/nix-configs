{
  imports = [
    ./zsh.nix
    ./git.nix
    ./ssh.nix
    ./gh.nix
  ];

  programs = {
    home-manager.enable = true;
    tmux.enable = true;
    vim.enable = true;
  };
}
