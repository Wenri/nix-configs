{pkgs, ...}: {
  home.packages = with pkgs; [
    tmux
    parted
    htop
    nodejs
    claude-code
    gh
  ];
}
